// Purpose: Orchestrates a hands-free voice assistant session over a project's
// SOW documents — context loading, Gemini Live session, live transcript turns,
// tool-call edits, and conversation history persistence.
import 'dart:async';

import 'package:buildercam/core/core.dart';
import 'package:flutter/foundation.dart';

import '../models/sow_chat_message.dart';
import '../models/sow_document_model.dart';
import '../models/sow_transcript_model.dart';
import '../services/shared_prefs_service.dart';
import '../services/sow_firestore_service.dart';
import '../services/sow_voice_agent_service.dart';

enum VoiceChatState {
  /// Fetching the project and its SOW documents.
  loading,

  /// Opening the Gemini Live session and the microphone.
  connecting,

  /// Live — mic open, agent silent.
  listening,

  /// Live — agent audio is playing.
  speaking,

  /// Session over (user ended it or the server closed the socket).
  ended,

  /// Unrecoverable failure — see [errorMessage].
  error,
}

class SowVoiceChatController extends ChangeNotifier {
  SowVoiceChatController({
    required this.projectId,
    required SowBackendService backend,
    SowSharedPrefsService? prefs,
  })  : _backend = backend,
        _prefs = prefs ?? SowSharedPrefsService();

  final String projectId;
  final SowBackendService _backend;
  final SowSharedPrefsService _prefs;

  SowVoiceAgentService? _service;
  StreamSubscription<SowVoiceEvent>? _eventSubscription;

  VoiceChatState _state = VoiceChatState.loading;
  String? _errorMessage;
  bool _muted = false;
  bool _historySaved = false;
  DateTime _startedAt = DateTime.now();

  SowProjectModel? _project;
  List<SowDocumentModel> _documents = [];

  /// Committed transcript turns, oldest first.
  final List<SowChatMessage> messages = [];

  /// In-progress transcription of the current user / agent turn.
  String userPartial = '';
  String agentPartial = '';

  VoiceChatState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get muted => _muted;
  String get projectName => _project?.name ?? '';
  int get documentCount => _documents.length;
  bool get isLive =>
      _state == VoiceChatState.listening || _state == VoiceChatState.speaking;

  // ── Session lifecycle ───────────────────────────────────────────────────────

  Future<void> start() async {
    _setState(VoiceChatState.loading);
    final String idToken;
    try {
      final results = await Future.wait([
        _backend.fetchProject(projectId),
        _backend.fetchSowDocuments(projectId),
      ]);
      _project = results[0] as SowProjectModel?;
      _documents = results[1] as List<SowDocumentModel>;
      if (_project == null) {
        _fail('Project not found.');
        return;
      }

      // The voice session runs through the backend WebSocket proxy, which
      // holds the Gemini API key. The Firebase ID token authenticates us.
      final token = await _backend.tokenProvider?.call();
      if (token == null || token.isEmpty) {
        _fail('Not signed in — cannot start a voice session.');
        return;
      }
      idToken = token;
    } catch (e) {
      _fail('Could not load project context: $e');
      return;
    }

    _setState(VoiceChatState.connecting);
    try {
      final service = createSowVoiceAgentService();
      _service = service;
      _eventSubscription = service.events.listen(_handleEvent);
      await service.connect(
        uri: buildVoiceAgentProxyUri(
          backendBaseUrl: ApiConfig.sowProxyBaseUrl,
          firebaseIdToken: idToken,
        ),
        systemInstruction: _buildSystemInstruction(),
      );
      _startedAt = DateTime.now();
      _setState(VoiceChatState.listening);
    } on UnsupportedError catch (e) {
      _fail(e.message ?? 'Voice assistant is not supported on this platform.');
    } catch (e) {
      _fail('Could not start the voice session: $e');
    }
  }

  Future<void> end() async {
    if (_state == VoiceChatState.ended) return;
    _commitUserPartial();
    _commitAgentPartial();
    await _service?.disconnect();
    _setState(VoiceChatState.ended);
    await _saveHistory();
  }

  void toggleMute() {
    _muted = !_muted;
    _service?.setMuted(_muted);
    notifyListeners();
  }

  @override
  void dispose() {
    _commitUserPartial();
    _commitAgentPartial();
    unawaited(_saveHistory());
    _eventSubscription?.cancel();
    _service?.dispose();
    super.dispose();
  }

  // ── Event handling ──────────────────────────────────────────────────────────

  void _handleEvent(SowVoiceEvent event) {
    switch (event) {
      case VoiceUserTranscriptDelta(:final text):
        // A fresh user turn while agent text is pending means the agent's
        // turn ended without a turnComplete (e.g. barge-in) — commit it.
        if (userPartial.isEmpty) _commitAgentPartial();
        userPartial += text;
        notifyListeners();

      case VoiceAgentTranscriptDelta(:final text):
        // The agent responding marks the end of the user's turn.
        _commitUserPartial();
        agentPartial += text;
        notifyListeners();

      case VoiceTurnComplete():
        _commitUserPartial();
        _commitAgentPartial();
        notifyListeners();

      case VoiceInterrupted():
        _commitAgentPartial();
        notifyListeners();

      case VoiceToolCall():
        unawaited(_executeToolCall(event));

      case VoiceSpeakingChanged(:final speaking):
        if (isLive) {
          _setState(
            speaking ? VoiceChatState.speaking : VoiceChatState.listening,
          );
        }

      case VoiceErrorEvent(:final message):
        if (kDebugMode) debugPrint('[SowVoiceChat] error: $message');
        // Surface errors that kill the session; transient ones during a live
        // session are logged but don't tear down the UI.
        if (!isLive) _fail(message);

      case VoiceDisconnected():
        if (_state != VoiceChatState.ended && _state != VoiceChatState.error) {
          unawaited(end());
        }
    }
  }

  void _commitUserPartial() {
    final text = userPartial.trim();
    userPartial = '';
    if (text.isNotEmpty) messages.add(SowChatMessage.user(text));
  }

  void _commitAgentPartial() {
    final text = agentPartial.trim();
    agentPartial = '';
    if (text.isNotEmpty) messages.add(SowChatMessage.bot(text));
  }

  // ── Tool execution ──────────────────────────────────────────────────────────

  Future<void> _executeToolCall(VoiceToolCall call) async {
    if (call.name != voiceToolUpdateSowDocument) {
      await _service?.sendToolResponse(call.id, call.name, {
        'success': false,
        'error': 'Unknown tool: ${call.name}',
      });
      return;
    }

    final documentId = call.args['documentId'] as String? ?? '';
    final updatedContent = call.args['updatedContent'] as String? ?? '';
    final index = _documents.indexWhere((d) => d.id == documentId);

    if (index == -1 || updatedContent.trim().isEmpty) {
      await _service?.sendToolResponse(call.id, call.name, {
        'success': false,
        'error': index == -1
            ? 'No SOW document with ID "$documentId" exists in this project.'
            : 'updatedContent must not be empty.',
      });
      return;
    }

    final doc = _documents[index];
    try {
      // The backend enforces edit permission — a member without
      // canEditDocument gets a 403 here, which is reported to the model.
      final saved = await _backend.saveSowDocument(
        projectId: projectId,
        id: doc.id,
        title: doc.title,
        content: updatedContent,
        transcriptIds: doc.transcriptIds,
        frameUrls: doc.frameUrls,
      );
      _documents[index] = saved;
      messages.add(SowChatMessage.bot('Updated "${doc.title}"', isEdit: true));
      notifyListeners();
      await _service?.sendToolResponse(call.id, call.name, {
        'success': true,
        'message': 'Document "${doc.title}" was updated and saved.',
      });
    } catch (e) {
      await _service?.sendToolResponse(call.id, call.name, {
        'success': false,
        'error': 'Saving failed: $e',
      });
    }
  }

  // ── Context prompt ──────────────────────────────────────────────────────────

  String _buildSystemInstruction() {
    final project = _project!;
    final sb = StringBuffer()
      ..writeln(
        'You are the BuilderCam voice assistant — a construction Scope of '
        'Work specialist having a spoken conversation with a contractor. '
        'You help them understand and edit the SOW documents of this project.',
      )
      ..writeln()
      ..writeln('PROJECT DETAILS:')
      ..writeln('  Project name : ${project.name}')
      ..writeln('  Client       : ${project.clientName}');
    if (project.siteLocation.isNotEmpty) {
      sb.writeln('  Site         : ${project.siteLocation}');
    }
    if (project.scopeSummary.isNotEmpty) {
      sb.writeln('  Scope note   : ${project.scopeSummary}');
    }
    if (project.notes.isNotEmpty) {
      sb.writeln('  Notes        : ${project.notes}');
    }

    sb
      ..writeln()
      ..writeln('SOW DOCUMENTS IN THIS PROJECT (${_documents.length}):');
    if (_documents.isEmpty) {
      sb.writeln(
        '  (none yet — the user can generate one from the Record tab)',
      );
    }
    for (final doc in _documents) {
      sb
        ..writeln()
        ..writeln('── DOCUMENT ID: ${doc.id} ──')
        ..writeln('Title: ${doc.title}')
        ..writeln(doc.content)
        ..writeln('── END DOCUMENT ${doc.id} ──');
    }

    sb
      ..writeln()
      ..writeln('HOW TO BEHAVE:')
      ..writeln(
        '- This is a voice conversation. Keep answers short and natural — '
        'one to three spoken sentences unless the user asks for detail.',
      )
      ..writeln(
        '- Never read a whole document aloud unless explicitly asked; '
        'summarise instead.',
      )
      ..writeln(
        '- To edit a document, call the $voiceToolUpdateSowDocument tool '
        'with the document ID and the COMPLETE updated text — change only '
        'what was requested and preserve everything else verbatim, keeping '
        'the original plain-text formatting and section numbering.',
      )
      ..writeln(
        '- Confirm with the user before making large or destructive changes.',
      )
      ..writeln(
        '- After the tool succeeds, briefly confirm what changed. If it '
        'fails, relay the reason.',
      )
      ..writeln(
        '- Do not invent costs, quantities, or specifications unless the '
        'user provides them.',
      )
      ..writeln(
        '- If a request is ambiguous (e.g. which document), ask one short '
        'clarifying question.',
      );

    return sb.toString();
  }

  // ── History ─────────────────────────────────────────────────────────────────

  Future<void> _saveHistory() async {
    if (_historySaved || messages.isEmpty) return;
    _historySaved = true;
    try {
      await _prefs.addVoiceConversation(
        SowVoiceConversation(
          projectId: projectId,
          projectName: projectName,
          startedAt: _startedAt,
          endedAt: DateTime.now(),
          messages: List<SowChatMessage>.of(messages),
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[SowVoiceChat] history save failed: $e');
    }
  }

  void _setState(VoiceChatState next) {
    if (_state == next) return;
    _state = next;
    notifyListeners();
  }

  void _fail(String message) {
    _errorMessage = message;
    _setState(VoiceChatState.error);
  }
}

// Purpose: Coordinates recording, live transcription, backend persistence, and history state.
import 'dart:async';
import 'dart:math' as math;

import 'package:buildercam/core/core.dart';
import 'package:flutter/foundation.dart';

import '../models/sow_log_entry.dart';
import '../models/sow_transcript_model.dart';
import '../services/gemini_live_service.dart';
import '../services/sow_firestore_service.dart';
import '../services/shared_prefs_service.dart';

enum RecordingState { idle, connecting, recording, saving, error }

enum DraftMode { autoFollow, manualEdit }

class SowRecordingController extends ChangeNotifier {
  SowRecordingController({
    required this.projectId,
    required this.createdBy,
    required SowBackendService sowBackendService,
    required GeminiLiveService geminiLiveService,
    required SowSharedPrefsService sharedPrefsService,
    Future<void> Function()? onAutosaveCompleted,
  }) : _sowBackendService = sowBackendService,
       _geminiLiveService = geminiLiveService,
       _sharedPrefsService = sharedPrefsService,
       _onAutosaveCompleted = onAutosaveCompleted;

  final String projectId;
  final String createdBy;
  final SowBackendService _sowBackendService;
  final GeminiLiveService _geminiLiveService;
  final SowSharedPrefsService _sharedPrefsService;
  final Future<void> Function()? _onAutosaveCompleted;

  // Autosave roughly every 10-15 words; 15 keeps the save cadence calm.
  static const int _autoSaveWordThreshold = 15;

  RecordingState recordingState = RecordingState.idle;
  String? activeTranscriptId;
  List<String> activeFrameUrls = const [];
  String liveTranscript = '';
  String draftTranscript = '';
  String _machineTranscript = '';
  String _baseAtFirstEdit = '';
  String _lastPersistedTranscript = '';
  int _lastAutoSavedWordCount = 0;
  DraftMode draftMode = DraftMode.autoFollow;
  bool hasLocalEdits = false;
  bool hasPendingResync = false;
  bool hasUnsavedChanges = false;
  DateTime? lastSyncedAt;
  DateTime? lastSavedAt;
  String? errorMessage;
  int elapsedSeconds = 0;
  List<SowTranscriptModel> history = <SowTranscriptModel>[];
  bool historyLoaded = false;
  List<SowLogEntry> logs = <SowLogEntry>[];

  StreamSubscription<String>? _liveTranscriptSubscription;
  StreamSubscription<GeminiLiveError>? _liveErrorSubscription;
  Timer? _elapsedTimer;
  Timer? _rebuildThrottle;
  bool _isPersistingDraft = false;
  bool _isDisposed = false;
  bool _pendingWordBoundary = false;

  bool get hasDraft => draftTranscript.trim().isNotEmpty;

  String get recordingActionLabel =>
      hasDraft ? 'Continue Recording' : 'Start Recording';

  String get saveActionLabel => 'Save Edits';

  Future<void> startRecording() async {
    if (recordingState == RecordingState.connecting ||
        recordingState == RecordingState.recording ||
        recordingState == RecordingState.saving) {
      return;
    }

    try {
      clearError(notify: false);
      _appendLog(
        source: SowLogSource.recorder,
        level: SowLogLevel.info,
        message: 'Connecting to Gemini Live.',
      );

      _prepareDraftForRecording();
      recordingState = RecordingState.connecting;
      _notifySafely();

      await _cancelLiveSubscriptions();
      await _geminiLiveService.connect(ApiConfig.geminiApiKey);
      _appendLog(
        source: SowLogSource.transcription,
        level: SowLogLevel.success,
        message: 'Gemini Live setup complete.',
      );

      _liveTranscriptSubscription = _geminiLiveService.transcriptStream.listen(
        _onLiveTranscript,
      );
      _liveErrorSubscription = _geminiLiveService.errorStream.listen(
        _onLiveServiceError,
      );

      await _geminiLiveService.startStreaming();
      recordingState = RecordingState.recording;
      _appendLog(
        source: SowLogSource.recorder,
        level: SowLogLevel.success,
        message: 'Microphone streaming started.',
      );

      _startTimer();
      _notifySafely();
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> stopRecording() async {
    if (recordingState != RecordingState.recording) {
      return;
    }

    try {
      _appendLog(
        source: SowLogSource.recorder,
        level: SowLogLevel.info,
        message: 'Stopping live transcription.',
      );
      recordingState = RecordingState.saving;
      _stopTimer();
      _notifySafely();

      await _geminiLiveService.stopStreaming();
      // Wait 2 seconds for any final transcript chunks to arrive before closing.
      await Future.delayed(const Duration(seconds: 2));
      await _cancelLiveSubscriptions();

      if (recordingState == RecordingState.error) {
        return;
      }

      recordingState = RecordingState.idle;
      hasUnsavedChanges = draftTranscript.trim().isNotEmpty;
      if (draftTranscript.trim().isEmpty) {
        _appendLog(
          source: SowLogSource.recorder,
          level: SowLogLevel.info,
          message: 'No speech was captured in this recording.',
        );
      } else {
        _appendLog(
          source: SowLogSource.recorder,
          level: SowLogLevel.success,
          message: 'Recording stopped. Review the transcript and tap Save when ready.',
        );
      }
      _notifySafely();
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> saveDraft({String? title}) async {
    if (recordingState == RecordingState.connecting ||
        recordingState == RecordingState.recording ||
        recordingState == RecordingState.saving) {
      return;
    }

    final transcript = draftTranscript.trim();
    if (transcript.isEmpty) {
      _setError(StateError('Draft is empty. Record or type transcript first.'));
      return;
    }

    // Snapshot state for rollback.
    final prevHistory = List<SowTranscriptModel>.unmodifiable(history);
    final prevDraft = draftTranscript;
    final prevActiveId = activeTranscriptId;
    final prevLastPersisted = _lastPersistedTranscript;
    final prevHasUnsaved = hasUnsavedChanges;
    final prevElapsed = elapsedSeconds;
    final currentFrameUrls = List<String>.unmodifiable(activeFrameUrls);
    final cleanTitle =
        title != null && title.trim().isNotEmpty ? title.trim() : null;
    final now = DateTime.now().toUtc();
    final isUpdate = prevActiveId != null;

    // --- Optimistic update: show result instantly without waiting for backend.
    final optimisticId = 'opt_${now.millisecondsSinceEpoch}';
    final optimisticEntry = SowTranscriptModel(
      id: isUpdate ? prevActiveId : optimisticId,
      projectId: projectId,
      rawTranscript: transcript,
      durationSeconds: prevElapsed,
      createdAt: now,
      updatedAt: now,
      createdBy: createdBy,
      status: SowTranscriptStatus.completed,
      title: cleanTitle,
      frameUrls: currentFrameUrls,
    );

    if (isUpdate) {
      history = [
        for (final t in history)
          if (t.id == prevActiveId) optimisticEntry else t,
      ];
    } else {
      history = [optimisticEntry, ...history];
    }
    historyLoaded = true;
    _resetDraftState();
    lastSavedAt = now;
    lastSyncedAt = now;
    _lastPersistedTranscript = transcript;
    hasUnsavedChanges = false;
    _appendLog(
      source: SowLogSource.backend,
      level: SowLogLevel.info,
      message: 'Saving transcript\u2026',
      details: '${transcript.length} characters \u2014 ${prevElapsed}s',
    );
    _notifySafely();

    // --- Background persist to backend ---
    try {
      final saved = await _sowBackendService.saveTranscript(
        projectId: projectId,
        id: isUpdate ? prevActiveId : null,
        text: transcript,
        duration: prevElapsed,
        createdAt: now,
        createdBy: createdBy,
        title: cleanTitle,
        frameUrls: currentFrameUrls,
      );
      activeTranscriptId = saved.id;
      lastSavedAt = saved.updatedAt ?? saved.createdAt;
      lastSyncedAt = lastSavedAt;
      history = [
        for (final t in history)
          if (t.id == optimisticEntry.id) saved else t,
      ];
      unawaited(_sharedPrefsService.clearDraft());
      _appendLog(
        source: SowLogSource.backend,
        level: SowLogLevel.success,
        message: 'Transcript saved.',
      );
      _notifySafely();
    } catch (error) {
      // Rollback the optimistic changes.
      history = prevHistory;
      draftTranscript = prevDraft;
      liveTranscript = prevDraft;
      _machineTranscript = prevDraft;
      activeTranscriptId = prevActiveId;
      activeFrameUrls = currentFrameUrls;
      _lastPersistedTranscript = prevLastPersisted;
      hasUnsavedChanges = prevHasUnsaved;
      elapsedSeconds = prevElapsed;
      _setError(error);
    }
  }

  void updateActiveFrameUrls(List<String> urls) {
    activeFrameUrls = List.unmodifiable(urls);
    _notifySafely();
  }

  void updateDraft(String value) {
    draftTranscript = value;
    hasUnsavedChanges =
        draftTranscript.trim() != _lastPersistedTranscript.trim();
    if (draftTranscript.trim().isEmpty) {
      activeTranscriptId = null;
    }

    final machine = _machineTranscript.trim();
    final edited = draftTranscript.trim();
    if (edited == machine) {
      draftMode = DraftMode.autoFollow;
      hasLocalEdits = false;
      hasPendingResync = false;
      _baseAtFirstEdit = _machineTranscript;
      _notifySafely();
      return;
    }

    if (draftMode == DraftMode.autoFollow) {
      draftMode = DraftMode.manualEdit;
      _baseAtFirstEdit = _machineTranscript;
    }

    hasLocalEdits = true;
    _notifySafely();
  }

  void resyncDraft() {
    if (_machineTranscript.trim().isEmpty) {
      return;
    }

    if (!hasLocalEdits) {
      draftTranscript = _machineTranscript;
      draftMode = DraftMode.autoFollow;
      hasPendingResync = false;
      hasUnsavedChanges =
          draftTranscript.trim() != _lastPersistedTranscript.trim();
      lastSyncedAt = DateTime.now();
      _notifySafely();
      return;
    }

    draftTranscript = _mergeEditedAndLatest(
      base: _baseAtFirstEdit,
      edited: draftTranscript,
      latest: _machineTranscript,
    );
    hasPendingResync = false;
    hasUnsavedChanges =
        draftTranscript.trim() != _lastPersistedTranscript.trim();
    hasLocalEdits = draftTranscript.trim() != _machineTranscript.trim();
    draftMode = hasLocalEdits ? DraftMode.manualEdit : DraftMode.autoFollow;
    _baseAtFirstEdit = _machineTranscript;
    lastSyncedAt = DateTime.now();
    _appendLog(
      source: SowLogSource.transcription,
      level: SowLogLevel.info,
      message: 'Draft resynced with the latest live transcript.',
    );
    _notifySafely();
  }

  Future<void> loadHistory(String projectId) async {
    try {
      history = await _sowBackendService.fetchHistory(projectId);
      historyLoaded = true;
      if (activeTranscriptId != null &&
          history.every((transcript) => transcript.id != activeTranscriptId)) {
        activeTranscriptId = null;
      }
      _appendLog(
        source: SowLogSource.backend,
        level: SowLogLevel.success,
        message: 'Loaded transcript history.',
        details:
            history.isEmpty
                ? 'No saved transcripts yet.'
                : '${history.length} saved transcript${history.length == 1 ? '' : 's'} available.',
      );
      _notifySafely();
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> restoreAutosavedDraft() async {
    if (_isDisposed || recordingState != RecordingState.idle) {
      return;
    }

    final snapshot = await _sharedPrefsService.loadDraft();
    if (snapshot == null) {
      return;
    }

    if (snapshot.projectId.isNotEmpty && snapshot.projectId != projectId) {
      return;
    }

    final transcript = snapshot.transcript.trim();
    if (transcript.isEmpty) {
      return;
    }

    activeTranscriptId = snapshot.transcriptId;
    draftTranscript = snapshot.transcript;
    liveTranscript = snapshot.transcript;
    _machineTranscript = snapshot.transcript;
    _baseAtFirstEdit = _machineTranscript;
    _lastPersistedTranscript = transcript;
    _lastAutoSavedWordCount = _countWords(transcript);
    draftMode = DraftMode.autoFollow;
    hasLocalEdits = false;
    hasPendingResync = false;
    hasUnsavedChanges = false;
    elapsedSeconds = snapshot.durationSeconds;
    lastSavedAt = snapshot.savedAt;
    lastSyncedAt = snapshot.savedAt;
    _appendLog(
      source: SowLogSource.backend,
      level: SowLogLevel.info,
      message: 'Restored autosaved draft from shared prefs.',
      details: '${transcript.length} characters recovered.',
    );
    _notifySafely();
  }

  Future<void> deleteTranscript(String transcriptId) async {
    // Snapshot for rollback.
    final prevHistory = List<SowTranscriptModel>.unmodifiable(history);
    final target = history.where((t) => t.id == transcriptId).firstOrNull;
    final wasActive = activeTranscriptId == transcriptId;

    // --- Optimistic remove: update UI instantly ---
    if (wasActive) {
      _resetDraftState();
    }
    history = history.where((t) => t.id != transcriptId).toList();
    _appendLog(
      source: SowLogSource.backend,
      level: SowLogLevel.info,
      message: 'Transcript deleted.',
    );
    _notifySafely();

    try {
      await _sowBackendService.deleteTranscript(projectId, transcriptId);
    } catch (error) {
      // Rollback.
      history = prevHistory;
      if (wasActive && target != null) {
        activeTranscriptId = target.id;
        activeFrameUrls = target.frameUrls;
        draftTranscript = target.rawTranscript;
        liveTranscript = target.rawTranscript;
        _machineTranscript = target.rawTranscript;
        _lastPersistedTranscript = target.rawTranscript.trim();
        hasUnsavedChanges = false;
      }
      _setError(error);
    }
  }

  void clearError({bool notify = true}) {
    errorMessage = null;
    if (recordingState == RecordingState.error) {
      recordingState = RecordingState.idle;
    }
    if (notify) {
      _notifySafely();
    }
  }

  Future<void> selectTranscript(
    SowTranscriptModel transcript, {
    bool notify = true,
  }) async {
    if (recordingState == RecordingState.connecting ||
        recordingState == RecordingState.recording ||
        recordingState == RecordingState.saving) {
      return;
    }

    // Auto-save the current draft before switching to avoid silent data loss.
    // Fire it in the background — don't block UI while the request is in-flight.
    final currentDraft = draftTranscript.trim();
    if (currentDraft.isNotEmpty &&
        currentDraft != _lastPersistedTranscript.trim()) {
      unawaited(_persistDraftSnapshot(
        allowWhileRecording: false,
        clearDraftAfterSave: false,
        persistSharedPrefs: false,
        refreshHistory: false,
        swallowErrors: true,
        logMessage: 'Auto-saving draft before switching transcript.',
        successMessage: 'Draft saved before switching.',
        failureMessage: 'Unable to auto-save draft before switching.',
      ));
    }

    activeTranscriptId = transcript.id;
    activeFrameUrls = transcript.frameUrls;
    draftTranscript = transcript.rawTranscript;
    liveTranscript = transcript.rawTranscript;
    _machineTranscript = transcript.rawTranscript;
    _baseAtFirstEdit = _machineTranscript;
    _lastPersistedTranscript = transcript.rawTranscript.trim();
    _lastAutoSavedWordCount = _countWords(_lastPersistedTranscript);
    draftMode = DraftMode.autoFollow;
    hasLocalEdits = false;
    hasPendingResync = false;
    hasUnsavedChanges = false;
    elapsedSeconds = transcript.durationSeconds;
    lastSavedAt = transcript.updatedAt ?? transcript.createdAt;
    lastSyncedAt = lastSavedAt;
    clearError(notify: false);
    _appendLog(
      source: SowLogSource.backend,
      level: SowLogLevel.info,
      message: 'Loaded transcript into the draft workspace.',
    );
    if (notify) {
      _notifySafely();
    }
  }

  Future<void> resetDraft({bool notify = true}) async {
    if (recordingState == RecordingState.connecting ||
        recordingState == RecordingState.recording ||
        recordingState == RecordingState.saving) {
      return;
    }

    // Auto-save the current draft to Firestore before clearing.
    // Fire in the background so the reset feels instant.
    // Don't bother saving to shared prefs — we clear them right after anyway.
    final transcript = draftTranscript.trim();
    if (transcript.isNotEmpty &&
        transcript != _lastPersistedTranscript.trim()) {
      unawaited(_persistDraftSnapshot(
        allowWhileRecording: false,
        clearDraftAfterSave: false,
        persistSharedPrefs: false,
        refreshHistory: true,
        swallowErrors: true,
        logMessage: 'Auto-saving draft before reset.',
        successMessage: 'Draft saved before reset.',
        failureMessage: 'Unable to auto-save draft before reset.',
      ));
    }

    _resetDraftState();
    unawaited(_sharedPrefsService.clearDraft());
    clearError(notify: false);
    _appendLog(
      source: SowLogSource.backend,
      level: SowLogLevel.info,
      message: 'Draft reset. The next recording will start a fresh transcript.',
    );
    if (notify) {
      _notifySafely();
    }
  }

  @override
  void dispose() {
    // Persist current draft to shared prefs so it survives navigation.
    if (draftTranscript.trim().isNotEmpty) {
      unawaited(
        _sharedPrefsService.saveDraft(
          projectId: projectId,
          transcript: draftTranscript.trim(),
          durationSeconds: elapsedSeconds,
          transcriptId: activeTranscriptId,
        ),
      );
    }
    _isDisposed = true;
    _stopTimer();
    _rebuildThrottle?.cancel();
    _liveTranscriptSubscription?.cancel();
    _liveErrorSubscription?.cancel();
    _geminiLiveService.dispose();
    super.dispose();
  }

  void _prepareDraftForRecording() {
    if (!hasDraft) {
      _resetDraftState();
      return;
    }

    _machineTranscript = draftTranscript.trim();
    liveTranscript = _machineTranscript;
    _baseAtFirstEdit = _machineTranscript;
    _lastPersistedTranscript = _machineTranscript;
    _lastAutoSavedWordCount = _countWords(_machineTranscript);
    draftMode = DraftMode.autoFollow;
    hasLocalEdits = false;
    hasPendingResync = false;
    hasUnsavedChanges = false;
  }

  void _resetDraftState() {
    activeTranscriptId = null;
    activeFrameUrls = const [];
    liveTranscript = '';
    draftTranscript = '';
    _machineTranscript = '';
    _baseAtFirstEdit = '';
    _lastPersistedTranscript = '';
    _lastAutoSavedWordCount = 0;
    draftMode = DraftMode.autoFollow;
    hasLocalEdits = false;
    hasPendingResync = false;
    hasUnsavedChanges = false;
    lastSyncedAt = null;
    elapsedSeconds = 0;
    _pendingWordBoundary = false;
  }

  void _onLiveTranscript(String incoming) {
    // Space-only fragment = Gemini signals a word boundary between chunks.
    // Don't drop it; record it so the next real fragment gets a leading space.
    if (incoming.trim().isEmpty) {
      if (incoming.contains(' ')) {
        _pendingWordBoundary = true;
        if (kDebugMode) {
          debugPrint('[SOW:transcription:debug] Word-boundary space received.');
        }
      }
      return;
    }

    // Honour a previously received word-boundary signal.
    if (_pendingWordBoundary) {
      _pendingWordBoundary = false;
      if (incoming.isNotEmpty && incoming[0] != ' ') {
        incoming = ' $incoming';
      }
    }

    if (kDebugMode) {
      debugPrint(
        '[SOW:transcription:debug] Incoming live transcript: $incoming',
      );
    }

    if (_isDuplicateTranscriptUpdate(_machineTranscript, incoming)) {
      return;
    }

    final merged = _mergeTranscript(_machineTranscript, incoming);
    if (merged == _machineTranscript) {
      return;
    }

    _machineTranscript = merged;
    liveTranscript = _machineTranscript;
    lastSyncedAt = DateTime.now();

    if (!hasLocalEdits) {
      draftTranscript = _machineTranscript;
      draftMode = DraftMode.autoFollow;
      hasPendingResync = false;
      _baseAtFirstEdit = _machineTranscript;
    } else {
      draftMode = DraftMode.manualEdit;
      hasPendingResync = true;
    }

    hasUnsavedChanges =
        draftTranscript.trim() != _lastPersistedTranscript.trim();
    if (kDebugMode) {
      debugPrint(
        '[SOW:transcription:debug] Draft updated to: $draftTranscript',
      );
    }
    _scheduledNotify();
    unawaited(_maybeAutoSaveDraft());
  }

  Future<void> _maybeAutoSaveDraft() async {
    if (_isDisposed ||
        _isPersistingDraft ||
        recordingState != RecordingState.recording ||
        draftMode != DraftMode.autoFollow ||
        hasLocalEdits) {
      return;
    }

    final transcript = draftTranscript.trim();
    if (transcript.isEmpty || transcript == _lastPersistedTranscript.trim()) {
      return;
    }

    final wordCount = _countWords(transcript);
    if (wordCount < _lastAutoSavedWordCount + _autoSaveWordThreshold) {
      return;
    }

    await _persistDraftSnapshot(
      allowWhileRecording: true,
      clearDraftAfterSave: false,
      persistSharedPrefs: true,
      refreshHistory: false,
      swallowErrors: true,
      logMessage: 'Auto-saving transcript snapshot.',
      successMessage: 'Transcript auto-saved.',
      failureMessage: 'Unable to auto-save the current transcript snapshot.',
    );
  }

  Future<bool> _persistDraftSnapshot({
    required bool allowWhileRecording,
    required bool clearDraftAfterSave,
    required bool persistSharedPrefs,
    required bool refreshHistory,
    required bool swallowErrors,
    required String logMessage,
    required String successMessage,
    required String failureMessage,
    String? details,
    String? title,
  }) async {
    if (_isPersistingDraft) {
      return false;
    }

    if (!allowWhileRecording &&
        (recordingState == RecordingState.connecting ||
            recordingState == RecordingState.recording ||
            recordingState == RecordingState.saving)) {
      return false;
    }

    final transcript = draftTranscript.trim();
    if (transcript.isEmpty) {
      return false;
    }

    final shouldExposeSavingState =
        recordingState == RecordingState.idle || clearDraftAfterSave;
    final previousState = recordingState;
    _isPersistingDraft = true;
    if (shouldExposeSavingState) {
      recordingState = RecordingState.saving;
    }

    _appendLog(
      source: SowLogSource.backend,
      level: SowLogLevel.info,
      message: logMessage,
      details:
          details ?? '${transcript.length} characters - ${elapsedSeconds}s',
    );
    _notifySafely();

    try {
      final savedTranscript = await _sowBackendService.saveTranscript(
        projectId: projectId,
        id: activeTranscriptId,
        text: transcript,
        duration: elapsedSeconds,
        createdAt: DateTime.now().toUtc(),
        createdBy: createdBy,
        title: title,
      );

      activeTranscriptId = savedTranscript.id;
      lastSavedAt = savedTranscript.updatedAt ?? savedTranscript.createdAt;
      lastSyncedAt = lastSavedAt;
      _lastPersistedTranscript = transcript;
      _lastAutoSavedWordCount = _countWords(transcript);
      hasUnsavedChanges = false;

      if (persistSharedPrefs) {
        await _sharedPrefsService.saveDraft(
          projectId: projectId,
          transcript: transcript,
          durationSeconds: elapsedSeconds,
          transcriptId: activeTranscriptId,
        );

        if (_onAutosaveCompleted != null) {
          await _onAutosaveCompleted();
        }
      } else {
        await _sharedPrefsService.clearDraft();
      }

      if (clearDraftAfterSave) {
        _resetDraftState();
        lastSavedAt = savedTranscript.updatedAt ?? savedTranscript.createdAt;
        lastSyncedAt = lastSavedAt;
      }

      if (refreshHistory) {
        await loadHistory(projectId);
      }

      _appendLog(
        source: SowLogSource.backend,
        level: SowLogLevel.success,
        message: successMessage,
        details: 'History and local snapshot updated.',
      );
      _notifySafely();
      return true;
    } catch (error) {
      if (swallowErrors) {
        _appendLog(
          source: SowLogSource.backend,
          level: SowLogLevel.error,
          message: failureMessage,
          details: error.toString(),
        );
        _notifySafely();
        return false;
      }

      rethrow;
    } finally {
      _isPersistingDraft = false;
      if (shouldExposeSavingState) {
        recordingState = previousState;
      }
      _notifySafely();
    }
  }

  int _countWords(String transcript) {
    final trimmed = transcript.trim();
    if (trimmed.isEmpty) {
      return 0;
    }

    return trimmed
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .length;
  }

  void _onLiveServiceError(GeminiLiveError error) {
    if (_isDisposed ||
        recordingState == RecordingState.idle ||
        recordingState == RecordingState.error) {
      return;
    }
    _setError(error);
  }

  Future<void> _cancelLiveSubscriptions() async {
    await _liveTranscriptSubscription?.cancel();
    await _liveErrorSubscription?.cancel();
    _liveTranscriptSubscription = null;
    _liveErrorSubscription = null;
  }

  String _mergeTranscript(String existing, String addition) {
    // Empty existing -> this is the very first fragment.
    if (existing.isEmpty) {
      return addition.trim();
    }

    // Addition is only whitespace -> nothing meaningful to add.
    if (addition.trim().isEmpty) {
      return existing.trimRight();
    }

    // Capture word-boundary signal BEFORE any trimming.
    // Gemini sends a leading space on `addition` to signal a new word boundary.
    // e.g. " my" = new word, "y" = mid-word continuation of previous fragment.
    final startsNewWord = addition.isNotEmpty && addition[0] == ' ';
    final fragment = addition.trim();
    final current = existing.trimRight();

    // Overlap detection (Gemini sometimes re-sends partial text).
    // Only applies to mid-word continuations — if Gemini signalled a new word
    // boundary (leading space), the fragment is a distinct word, never an overlap.
    // Cap at 8 chars to prevent false-positive matches on short common fragments.
    if (!startsNewWord) {
      final maxOverlap = math.min(8, math.min(current.length, fragment.length));
      for (var overlap = maxOverlap; overlap >= 1; overlap--) {
        if (current.toLowerCase().endsWith(
          fragment.substring(0, overlap).toLowerCase(),
        )) {
          final remaining = fragment.substring(overlap);
          // Entire fragment already present -> true duplicate, nothing to add.
          if (remaining.isEmpty) return current;
          // Partial overlap -> remaining is always a mid-word suffix, no space.
          return '$current$remaining';
        }
      }
    }

    // No overlap: append with correct spacing.
    return startsNewWord ? '$current $fragment' : '$current$fragment';
  }

  bool _isDuplicateTranscriptUpdate(String existing, String addition) {
    final normalizedAddition = _normalizeForCompare(addition);
    if (normalizedAddition.isEmpty) return true;

    final normalizedExisting = _normalizeForCompare(existing);
    if (normalizedExisting.isEmpty) return false;

    // Only skip if the full transcript IS the addition (exact full duplicate).
    // DO NOT use endsWith — fragments like "is", "to", "and", "am" are
    // common English words that legitimately repeat and must never be silently dropped.
    return normalizedExisting == normalizedAddition;
  }

  String _normalizeForCompare(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _startTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsedSeconds += 1;
      _notifySafely();
    });
  }

  void _stopTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  void _setError(Object error) {
    _stopTimer();
    unawaited(_geminiLiveService.stopStreaming());
    unawaited(_cancelLiveSubscriptions());
    recordingState = RecordingState.error;
    errorMessage =
        error is GeminiLiveError
            ? error.message
            : error.toString().replaceFirst('Bad state: ', '');
    _appendLog(
      source: SowLogSource.recorder,
      level: SowLogLevel.error,
      message: 'SOW recording flow hit an error.',
      details: errorMessage,
    );
    _notifySafely();
  }

  String _mergeEditedAndLatest({
    required String base,
    required String edited,
    required String latest,
  }) {
    final normalizedBase = base.trim();
    final normalizedEdited = edited.trim();
    final normalizedLatest = latest.trim();

    if (normalizedEdited.isEmpty) {
      return normalizedLatest;
    }

    if (normalizedBase.isEmpty || normalizedEdited == normalizedBase) {
      return normalizedLatest;
    }

    if (normalizedLatest == normalizedEdited) {
      return normalizedEdited;
    }

    if (normalizedLatest.startsWith(normalizedBase)) {
      final appended = normalizedLatest.substring(normalizedBase.length).trim();
      if (appended.isEmpty || normalizedEdited.contains(appended)) {
        return normalizedEdited;
      }
      return '$normalizedEdited $appended'
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    if (normalizedEdited.contains(normalizedLatest)) {
      return normalizedEdited;
    }

    if (normalizedLatest.contains(normalizedEdited)) {
      return normalizedLatest;
    }

    return '$normalizedEdited $normalizedLatest';
  }

  void _notifySafely() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  void _scheduledNotify() {
    _rebuildThrottle?.cancel();
    _rebuildThrottle = Timer(const Duration(milliseconds: 16), _notifySafely);
  }

  void _appendLog({
    required String source,
    required String level,
    required String message,
    String? details,
  }) {
    logs = <SowLogEntry>[
      SowLogEntry(
        source: source,
        level: level,
        message: message,
        details: details,
      ),
      ...logs,
    ].take(80).toList(growable: false);

    if (kDebugMode) {
      debugPrint('[SOW:$source:$level] $message ${details ?? ''}'.trim());
    }
  }
}

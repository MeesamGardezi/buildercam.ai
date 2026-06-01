// Purpose: Calls the Gemini REST API to generate a Scope of Work document.
import 'dart:convert';

import 'package:buildercam/core/core.dart';
import 'package:http/http.dart' as http;

import '../models/sow_transcript_model.dart';

class SowGenerationService {
  const SowGenerationService();

  static const String _model = 'gemini-2.0-flash';

  Future<String> generateSow({
    required SowProjectModel project,
    required List<SowTranscriptModel> transcripts,
  }) async {
    if (!ApiConfig.isGeminiConfigured) {
      throw Exception(
        'Gemini API key not configured. '
        'Pass --dart-define=GEMINI_API_KEY=... at build time.',
      );
    }
    if (transcripts.isEmpty) {
      throw Exception('Select at least one transcript to generate a SOW.');
    }

    final response = await http.post(
      Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent'
        '?key=${ApiConfig.geminiApiKey}',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': _buildPrompt(project, transcripts)},
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0.2,
          'maxOutputTokens': 8192,
        },
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Gemini API error ${response.statusCode}: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Gemini returned no candidates.');
    }

    final parts =
        (candidates.first['content'] as Map<String, dynamic>?)?['parts']
            as List<dynamic>?;
    if (parts == null || parts.isEmpty) {
      throw Exception('Gemini returned an empty response.');
    }

    return parts.first['text'] as String? ?? '';
  }

  String _buildPrompt(
    SowProjectModel project,
    List<SowTranscriptModel> transcripts,
  ) {
    final sb = StringBuffer()
      ..writeln(
        'You are a professional construction estimator. '
        'Generate a detailed, professional Scope of Work (SOW) document '
        'based on the following voice recordings captured during a site visit.',
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
      ..writeln('VOICE RECORDINGS (${transcripts.length}):');

    for (final (i, t) in transcripts.indexed) {
      final label =
          t.title?.trim().isNotEmpty == true ? t.title!.trim() : 'Recording ${i + 1}';
      sb
        ..writeln()
        ..writeln('── $label ──')
        ..writeln(t.rawTranscript.trim());
    }

    sb
      ..writeln()
      ..writeln('Generate a structured SOW document with these sections:')
      ..writeln('1. Project Overview')
      ..writeln('2. Scope of Work  (numbered line items, be specific)')
      ..writeln('3. Materials Required  (list items with estimated quantities)')
      ..writeln('4. Labour Estimate  (tasks and estimated hours)')
      ..writeln('5. Exclusions')
      ..writeln('6. Notes & Assumptions')
      ..writeln()
      ..writeln(
        'Be specific and professional. '
        'Extract all actionable items from the recordings. '
        'Do NOT invent pricing unless explicitly mentioned. '
        'Use plain text — no markdown symbols.',
      );

    return sb.toString();
  }
}

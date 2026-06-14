// Purpose: Exports the SOW transcription feature and its route constants.
export 'controllers/sow_recording_controller.dart';
export 'controllers/video_feed_controller.dart';
export 'models/captured_frame.dart';
export 'models/sow_document_model.dart';
export 'models/sow_transcript_model.dart';
export 'models/pdf_document_model.dart';
export 'services/gemini_live_service.dart';
export 'services/socket_sync_service.dart';
export 'services/sow_firestore_service.dart';
export 'services/video_frame_storage_service.dart';
export 'views/screens/sow_document_screen.dart';
export 'views/screens/sow_home_screen.dart';
export 'views/screens/sow_history_screen.dart';
export 'views/screens/sow_recording_screen.dart';
export 'views/screens/sow_settings_screen.dart';
export 'views/screens/sow_voice_chat_screen.dart';
export 'views/screens/sow_voice_history_screen.dart';
export 'views/screens/video_feed_screen.dart';
export 'views/widgets/recording_control_button.dart';
export 'views/widgets/recording_status_bar.dart';
export 'views/widgets/transcript_history_tile.dart';
export 'views/widgets/transcript_live_display.dart';

class SowTranscriptionRoutes {
  static const String recording = '/sow-recording';
  static const String videoFeed = '/video-feed';
}

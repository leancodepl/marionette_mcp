/// Shared app connection, session reporting, and recording runtime.
///
/// Both CLI adapters and MCP tools use this supported package boundary.
library;

export 'src/formatting.dart';
export 'src/session/session.dart';
export 'src/session/session_manager.dart';
export 'src/session/report_steps.dart';
export 'src/video/ffmpeg_process.dart';
export 'src/video/frame_protocol.dart';
export 'src/video/recording_session.dart';
export 'src/video/tcp_frame_reader.dart';
export 'src/video/video_options.dart';
export 'src/video/video_recorder.dart';
export 'src/video/ws_frame_server.dart';
export 'src/vm_service/vm_service_connector.dart';

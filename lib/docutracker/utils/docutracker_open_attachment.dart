import 'docutracker_open_attachment_io.dart'
    if (dart.library.html) 'docutracker_open_attachment_web.dart'
    as docutracker_open_attachment;

Future<void> openDocuTrackerAttachmentBytes(
  List<int> bytes,
  String filename,
) =>
    docutracker_open_attachment.openDocuTrackerAttachmentBytes(bytes, filename);

import 'dart:ui';

import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';

Rect docuTrackerSignatureRect(DocuTrackerSignatureField field, Size pageSize) =>
    Rect.fromLTWH(
      field.x * pageSize.width,
      field.y * pageSize.height,
      field.width * pageSize.width,
      field.height * pageSize.height,
    );

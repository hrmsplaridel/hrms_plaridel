import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hrms_plaridel/core/api/config.dart';
import 'package:hrms_plaridel/core/utils/form_pdf.dart';
import 'package:hrms_plaridel/features/docutracker/data/providers/docutracker_provider.dart';
import 'package:hrms_plaridel/features/docutracker/models/document.dart';
import 'package:hrms_plaridel/features/docutracker/models/linked_source_document.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_error_banner.dart';
import 'package:hrms_plaridel/features/docutracker/presentation/shared/widgets/docutracker_responsive_body.dart';
import 'package:hrms_plaridel/features/docutracker/theme/docutracker_tokens.dart';
import 'package:hrms_plaridel/features/learning_development/models/training_daily_report.dart';
import 'package:hrms_plaridel/features/recruitment/models/recruitment_application.dart';
import 'package:hrms_plaridel/features/recruitment/utils/rsp_applications_report_export.dart';

class DocuTrackerLinkedSourceDocumentScreen extends StatefulWidget {
  const DocuTrackerLinkedSourceDocumentScreen({
    super.key,
    required this.document,
  });

  final DocuTrackerDocument document;

  @override
  State<DocuTrackerLinkedSourceDocumentScreen> createState() =>
      _DocuTrackerLinkedSourceDocumentScreenState();
}

class _DocuTrackerLinkedSourceDocumentScreenState
    extends State<DocuTrackerLinkedSourceDocumentScreen> {
  DocuTrackerLinkedSourceDocument? _source;
  bool _loading = true;
  bool _printing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _message(Object error) =>
      error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

  Future<void> _load() async {
    final module = widget.document.sourceModule;
    final table = widget.document.sourceTable;
    final recordId = widget.document.sourceRecordId;
    if (module == null || table == null || recordId == null) {
      setState(() {
        _loading = false;
        _error = 'This linked document is incomplete.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final source = await context
          .read<DocuTrackerProvider>()
          .loadLinkedSourceDocument(
            sourceModule: module,
            sourceTable: table,
            sourceRecordId: recordId,
          );
      if (!mounted) return;
      setState(() {
        _source = source;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _openAttachment(
    DocuTrackerLinkedSourceAttachment attachment,
  ) async {
    final base = ApiConfig.baseUrl.replaceAll(RegExp(r'/$'), '');
    final raw = attachment.url.startsWith('http')
        ? attachment.url
        : '$base${attachment.url.startsWith('/') ? '' : '/'}${attachment.url}';
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.platformDefault)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The attachment could not be opened.')),
      );
    }
  }

  Future<void> _printSource() async {
    final source = _source;
    if (source == null || source.printData.isEmpty || _printing) return;
    setState(() => _printing = true);
    try {
      if (source.sourceModule == 'ld') {
        await FormPdf.printTrainingDailyReport(
          TrainingDailyReport.fromJson(source.printData),
        );
      } else if (source.sourceModule == 'rsp') {
        final application = RecruitmentApplication.fromJson(source.printData);
        await RspApplicationsReportExport.printPdf(
          context: context,
          rows: [RspApplicationsReportRow.fromApplication(app: application)],
          filterSummary: 'Application ${application.applicantNumber ?? ''}',
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The document could not be printed.')),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  String get _moduleLabel =>
      widget.document.sourceModule == 'ld' ? 'L&D document' : 'RSP document';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DocuTrackerTokens.canvasOf(context),
      appBar: AppBar(title: Text(_moduleLabel)),
      body: DocuTrackerResponsiveBody(
        maxWidth: 920,
        padding: const EdgeInsets.all(20),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DocuTrackerErrorBanner(message: _error!),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try Again'),
                  ),
                ],
              )
            : _buildDocument(_source!),
      ),
    );
  }

  Widget _buildDocument(DocuTrackerLinkedSourceDocument source) {
    return SingleChildScrollView(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: DocuTrackerTokens.cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              source.sourceModule == 'ld'
                  ? 'LEARNING AND DEVELOPMENT'
                  : 'RECRUITMENT, SELECTION AND PLACEMENT',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: DocuTrackerTokens.brand,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              source.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: DocuTrackerTokens.textPrimaryOf(context),
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Status: ${_displayValue(source.status)}',
              textAlign: TextAlign.center,
              style: DocuTrackerTokens.subtitleStyle(context),
            ),
            const SizedBox(height: 14),
            Center(
              child: FilledButton.icon(
                key: const ValueKey('docutracker-print-source-document'),
                onPressed: _printing ? null : _printSource,
                icon: _printing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.print_rounded),
                label: Text(_printing ? 'Preparing Print…' : 'Print'),
              ),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns = constraints.maxWidth >= 620;
                final width = twoColumns
                    ? (constraints.maxWidth - 16) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 16,
                  runSpacing: 14,
                  children: [
                    for (final item in source.fields)
                      SizedBox(
                        width: width,
                        child: _SourceField(field: item),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 26),
            Text(
              'Attachments',
              style: TextStyle(
                color: DocuTrackerTokens.textPrimaryOf(context),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            if (source.attachments.isEmpty)
              Text(
                'No attachments submitted.',
                style: DocuTrackerTokens.subtitleStyle(context),
              )
            else
              for (final attachment in source.attachments)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.attach_file_rounded),
                    title: Text(attachment.label),
                    subtitle: Text(
                      attachment.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.open_in_new_rounded),
                    onTap: () => _openAttachment(attachment),
                  ),
                ),
            const SizedBox(height: 20),
            Text(
              source.sourceModule == 'ld'
                  ? 'This record remains managed by the L&D module.'
                  : 'This application remains managed by the RSP module.',
              textAlign: TextAlign.center,
              style: DocuTrackerTokens.subtitleStyle(
                context,
              ).copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  String _displayValue(String value) {
    final normalized = value.replaceAll('_', ' ').trim();
    if (normalized.isEmpty) return 'Not provided';
    return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
  }
}

class _SourceField extends StatelessWidget {
  const _SourceField({required this.field});

  final DocuTrackerLinkedSourceField field;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DocuTrackerTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DocuTrackerTokens.borderSubtleOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field.label,
            style: DocuTrackerTokens.subtitleStyle(
              context,
            ).copyWith(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            field.value,
            style: TextStyle(
              color: DocuTrackerTokens.textPrimaryOf(context),
              fontSize: 14,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

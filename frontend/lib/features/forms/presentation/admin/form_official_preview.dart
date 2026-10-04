import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';

import 'package:hrms_plaridel/core/theme/app_theme.dart';

/// Official-form preview: one paper page at a time, with print and PDF actions.
class FormOfficialPreviewWorkspace extends StatelessWidget {
  const FormOfficialPreviewWorkspace({
    super.key,
    required this.title,
    required this.recordTitle,
    required this.meta,
    required this.format,
    required this.pages,
    required this.pageIndex,
    required this.zoom,
    required this.fitMode,
    required this.showThumbs,
    required this.showSettings,
    required this.printing,
    required this.downloading,
    required this.paperLabel,
    required this.orientationLabel,
    required this.onBack,
    required this.onPage,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFitWidth,
    required this.onFitPage,
    required this.onToggleThumbs,
    required this.onToggleSettings,
    required this.onPrint,
    required this.onDownload,
  });

  final String title;
  final String recordTitle;
  final String meta;
  final PdfPageFormat format;
  final List<Uint8List> pages;
  final int pageIndex;
  final double zoom;
  final String fitMode;
  final bool showThumbs;
  final bool showSettings;
  final bool printing;
  final bool downloading;
  final String paperLabel;
  final String orientationLabel;
  final VoidCallback onBack;
  final ValueChanged<int> onPage;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFitWidth;
  final VoidCallback onFitPage;
  final VoidCallback onToggleThumbs;
  final VoidCallback onToggleSettings;
  final VoidCallback onPrint;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final pageCount = pages.length;
    final index = pageCount == 0
        ? 0
        : pageIndex.clamp(0, pageCount - 1).toInt();
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final compact = constraints.maxWidth < 720;
        final thumbs = wide && showThumbs && pageCount > 1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                color: AppTheme.dashTextPrimaryOf(context),
                fontSize: compact ? 20 : 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$recordTitle  ·  $meta',
              style: TextStyle(
                color: AppTheme.dashTextSecondaryOf(context),
                fontSize: 13.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            _toolbar(
              context,
              compact: compact,
              pageCount: pageCount,
              index: index,
            ),
            if (showSettings) ...[
              const SizedBox(height: 8),
              _settings(context),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: math.max(
                460.0,
                MediaQuery.sizeOf(context).height * (compact ? 0.62 : 0.7),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.dashIsDark(context)
                      ? const Color(0xFF2C3138)
                      : const Color(0xFFE6E4E1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (thumbs)
                      _rail(context, index: index, pageCount: pageCount),
                    Expanded(
                      child: _paper(context, index: index, compact: compact),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            _footer(context, index: index, pageCount: pageCount),
          ],
        );
      },
    );
  }

  Widget _toolbar(
    BuildContext context, {
    required bool compact,
    required int pageCount,
    required int index,
  }) {
    final pageControl = DropdownButton<int>(
      value: pageCount == 0 ? null : index,
      isExpanded: compact,
      underline: const SizedBox.shrink(),
      items: [
        for (var i = 0; i < pageCount; i++)
          DropdownMenuItem(value: i, child: Text('Page ${i + 1} of $pageCount')),
      ],
      onChanged: pageCount == 0
          ? null
          : (value) {
              if (value != null) onPage(value);
            },
    );
    final zoom = Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton(
          tooltip: 'Zoom out',
          onPressed: onZoomOut,
          icon: const Icon(Icons.remove_rounded),
        ),
        Text(
          '${(this.zoom * 100).round()}%',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontWeight: FontWeight.w700,
          ),
        ),
        IconButton(
          tooltip: 'Zoom in',
          onPressed: onZoomIn,
          icon: const Icon(Icons.add_rounded),
        ),
        TextButton(
          onPressed: onFitWidth,
          child: const Text('Fit width'),
        ),
        TextButton(onPressed: onFitPage, child: const Text('Fit page')),
      ],
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: downloading ? null : onDownload,
          icon: downloading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: const Text('Download PDF'),
        ),
        FilledButton.icon(
          onPressed: printing ? null : onPrint,
          icon: printing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.print_rounded, size: 18),
          label: const Text('Print'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryNavy,
          ),
        ),
      ],
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Back'),
            ),
          ),
          pageControl,
          const SizedBox(height: 8),
          zoom,
          const SizedBox(height: 8),
          actions,
        ],
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Back'),
        ),
        pageControl,
        zoom,
        actions,
        IconButton(
          tooltip: showSettings ? 'Hide print settings' : 'Print settings',
          onPressed: onToggleSettings,
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
    );
  }

  Widget _settings(BuildContext context) {
    final secondary = AppTheme.dashTextSecondaryOf(context);
    Widget item(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(right: 22, bottom: 6),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '$label  '),
              TextSpan(
                text: value,
                style: TextStyle(
                  color: AppTheme.dashTextPrimaryOf(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          style: TextStyle(color: secondary, fontSize: 13),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: AppTheme.dashPanelOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dashHairlineOf(context)),
      ),
      child: Wrap(
        children: [
          item('Paper', paperLabel),
          item('Orientation', orientationLabel),
          item('Scale', '100%'),
          item('Margins', 'Official'),
        ],
      ),
    );
  }

  Widget _rail(
    BuildContext context, {
    required int index,
    required int pageCount,
  }) {
    return Container(
      width: 112,
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pages',
                  style: TextStyle(
                    color: AppTheme.dashTextSecondaryOf(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Hide pages',
                onPressed: onToggleThumbs,
                icon: const Icon(Icons.chevron_left_rounded, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          Expanded(
            child: ListView.separated(
              itemCount: pageCount,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final selected = i == index;
                return InkWell(
                  onTap: () => onPage(i),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: selected ? AppTheme.primaryNavy : Colors.white,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.memory(pages[i], fit: BoxFit.cover, height: 92),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _paper(
    BuildContext context, {
    required int index,
    required bool compact,
  }) {
    if (pages.isEmpty) {
      return const Center(child: Text('Unable to load preview.'));
    }
    final aspect = format.width / format.height;
    return LayoutBuilder(
      builder: (context, constraints) {
        final pad = compact ? 12.0 : 28.0;
        final maxW = math.max(80.0, constraints.maxWidth - pad * 2);
        final maxH = math.max(80.0, constraints.maxHeight - pad * 2);
        var width = maxW * zoom;
        if (fitMode == 'width') width = maxW;
        if (fitMode == 'page') width = math.min(maxW, maxH * aspect);
        return SingleChildScrollView(
          padding: EdgeInsets.all(pad),
          child: Center(
            child: Container(
              width: width,
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: AspectRatio(
                aspectRatio: aspect,
                child: Image.memory(pages[index], fit: BoxFit.fill),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _footer(
    BuildContext context, {
    required int index,
    required int pageCount,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final previous = IconButton(
          tooltip: 'Previous page',
          onPressed: index <= 0 ? null : () => onPage(index - 1),
          icon: const Icon(Icons.chevron_left_rounded),
        );
        final next = IconButton(
          tooltip: 'Next page',
          onPressed: index >= pageCount - 1 ? null : () => onPage(index + 1),
          icon: const Icon(Icons.chevron_right_rounded),
        );
        final label = Text(
          pageCount == 0 ? '—' : 'Page ${index + 1} / $pageCount',
          style: TextStyle(
            color: AppTheme.dashTextPrimaryOf(context),
            fontWeight: FontWeight.w700,
          ),
        );
        return Row(
          children: [
            if (constraints.maxWidth >= 640 && !showThumbs && pageCount > 1)
              TextButton.icon(
                onPressed: onToggleThumbs,
                icon: const Icon(Icons.view_sidebar_outlined, size: 18),
                label: const Text('Pages'),
              ),
            const Spacer(),
            previous,
            label,
            next,
            const Spacer(),
          ],
        );
      },
    );
  }
}

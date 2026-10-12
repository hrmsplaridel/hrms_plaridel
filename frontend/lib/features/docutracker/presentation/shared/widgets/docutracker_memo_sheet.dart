import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import 'package:hrms_plaridel/features/docutracker/models/document_builder.dart';
import 'package:hrms_plaridel/features/docutracker/models/docutracker_memo_template.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_memo_layout.dart';
import 'package:hrms_plaridel/features/docutracker/utils/docutracker_release_text.dart';

const _memoInk = Color(0xFF111827);

/// Quill styles for the Memo body: the same font, size and line height the
/// PDF uses, so the builder wraps the body at the same words.
quill.DefaultStyles docuTrackerMemoBodyStyles() {
  const style = TextStyle(
    fontFamily: DocuTrackerMemoLayout.fontFamily,
    fontSize: DocuTrackerMemoLayout.bodyFontSize,
    height: DocuTrackerMemoLayout.bodyLineHeight,
    color: _memoInk,
    decoration: TextDecoration.none,
  );
  return const quill.DefaultStyles(
    paragraph: quill.DefaultTextBlockStyle(
      style,
      quill.HorizontalSpacing.zero,
      quill.VerticalSpacing.zero,
      quill.VerticalSpacing.zero,
      null,
    ),
    lists: quill.DefaultListBlockStyle(
      style,
      quill.HorizontalSpacing.zero,
      quill.VerticalSpacing.zero,
      quill.VerticalSpacing(0, DocuTrackerMemoLayout.listItemGap),
      null,
      null,
    ),
    leading: quill.DefaultTextBlockStyle(
      style,
      quill.HorizontalSpacing.zero,
      quill.VerticalSpacing.zero,
      quill.VerticalSpacing.zero,
      null,
    ),
  );
}

/// Official Memorandum page as laid out in the document builder.
///
/// The letterhead, title, field labels, signatory blocks and footer are fixed
/// widgets; only To, Subject, Date, the body and CC are editable. A signatory
/// block prints its assigned signer's name and position; the only interactive
/// part is its signature area, and only for that signer.
class DocuTrackerMemoSheet extends StatelessWidget {
  const DocuTrackerMemoSheet({
    super.key,
    required this.size,
    required this.toController,
    required this.subjectController,
    required this.dateController,
    required this.ccController,
    required this.body,
    required this.editable,
    this.preparedBy = const DocuTrackerMemoSignatory(
      DocuTrackerMemoSlot.preparedBy,
      null,
    ),
    this.approvedBy = const DocuTrackerMemoSignatory(
      DocuTrackerMemoSlot.approvedBy,
      null,
    ),
    this.onSign,
    this.release,
  });

  final DocuTrackerMemoSignatory preparedBy;
  final DocuTrackerMemoSignatory approvedBy;

  /// Called when the assigned signer taps their signature area; null makes
  /// every signature area read-only.
  final ValueChanged<DocuTrackerSignatureField>? onSign;

  final Size size;
  final TextEditingController toController;
  final TextEditingController subjectController;
  final TextEditingController dateController;
  final TextEditingController ccController;
  final Widget body;
  final bool editable;

  /// Backend release details; null hides the release block entirely.
  final DocuTrackerMemoRelease? release;

  static const _text = _memoInk;

  Rect _rect(Rect fraction) => Rect.fromLTWH(
    fraction.left * size.width,
    fraction.top * size.height,
    fraction.width * size.width,
    fraction.height * size.height,
  );

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(
      fontSize: 14.5,
      fontWeight: FontWeight.w700,
      color: _text,
    );
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: DocuTrackerMemoLayout.fontFamily,
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          fontFamily: DocuTrackerMemoLayout.fontFamily,
          fontSize: DocuTrackerMemoLayout.metadataFontSize,
          color: _text,
        ),
        child: ColoredBox(
          color: Colors.white,
          child: Stack(
            children: [
              ..._letterhead(),
              Positioned(
                left: DocuTrackerMemoLayout.marginX * size.width,
                top: DocuTrackerMemoLayout.titleTop * size.height,
                child: const Text(
                  DocuTrackerMemoLayout.title,
                  key: ValueKey('memo-title'),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 8,
                    color: _text,
                  ),
                ),
              ),
              Positioned(
                left: DocuTrackerMemoLayout.marginX * size.width,
                right: DocuTrackerMemoLayout.marginX * size.width,
                top: DocuTrackerMemoLayout.metadataTop * size.height,
                bottom:
                    (1 - DocuTrackerMemoLayout.closingTop + 0.01) * size.height,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _metadataRow(
                      'To',
                      toController,
                      key: const ValueKey('memo-field-to'),
                      hint: 'Recipients, one per line',
                      maxLines: DocuTrackerMemoLayout.toMaxLines,
                      maxLength: DocuTrackerMemoTemplate.maxToLength,
                    ),
                    _metadataRow(
                      'Subject',
                      subjectController,
                      key: const ValueKey('memo-field-subject'),
                      hint: 'Subject',
                      maxLines: DocuTrackerMemoLayout.subjectMaxLines,
                      maxLength: DocuTrackerMemoTemplate.maxSubjectLength,
                    ),
                    _metadataRow(
                      'Date',
                      dateController,
                      key: const ValueKey('memo-field-date'),
                      hint: 'Month Day, Year',
                      maxLines: 1,
                      maxLength: DocuTrackerMemoTemplate.maxDateLength,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      key: const ValueKey('memo-divider'),
                      height: 2.4,
                      color: _text,
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: KeyedSubtree(
                        key: const ValueKey('memo-body'),
                        child: body,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: DocuTrackerMemoLayout.preparedLabelLeft * size.width,
                top: DocuTrackerMemoLayout.preparedLabelTop * size.height,
                child: const Text(
                  'Prepared by:',
                  key: ValueKey('memo-prepared-label'),
                  style: labelStyle,
                ),
              ),
              Positioned(
                left: DocuTrackerMemoLayout.approvedLabelLeft * size.width,
                top: DocuTrackerMemoLayout.approvedLabelTop * size.height,
                child: const Text(
                  'Approved by:',
                  key: ValueKey('memo-approved-label'),
                  style: labelStyle,
                ),
              ),
              Positioned.fromRect(
                rect: _rect(DocuTrackerMemoLayout.preparedField),
                child: _SignatoryBlock(signatory: preparedBy, onSign: onSign),
              ),
              Positioned.fromRect(
                rect: _rect(DocuTrackerMemoLayout.approvedField),
                child: _SignatoryBlock(signatory: approvedBy, onSign: onSign),
              ),
              Positioned(
                left: DocuTrackerMemoLayout.ccLeft * size.width,
                top: DocuTrackerMemoLayout.ccTop * size.height,
                width: DocuTrackerMemoLayout.ccWidth * size.width,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(
                      width: 44,
                      child: Text('Cc:', style: labelStyle),
                    ),
                    Expanded(
                      child: _value(
                        ccController,
                        key: const ValueKey('memo-field-cc'),
                        hint: 'Distribution, one per line',
                        maxLines: DocuTrackerMemoLayout.ccMaxLines,
                        maxLength: DocuTrackerMemoTemplate.maxCcLength,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (release != null)
                Positioned.fromRect(
                  rect: _rect(DocuTrackerMemoLayout.releaseBlock),
                  child: _ReleaseBlock(release: release!),
                ),
              ..._footer(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _letterhead() {
    Widget asset(String path) => Image.asset(
      path,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    final peach = _rect(DocuTrackerMemoLayout.peachBand);
    return [
      Positioned.fromRect(
        key: const ValueKey('memo-seal'),
        rect: _rect(DocuTrackerMemoLayout.seal),
        child: asset(DocuTrackerMemoLayout.sealAsset),
      ),
      Positioned(
        key: const ValueKey('memo-header'),
        left: DocuTrackerMemoLayout.headingLeft * size.width,
        top: DocuTrackerMemoLayout.headingTop * size.height,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DocuTrackerMemoLayout.republic,
              style: TextStyle(fontSize: 12.5, color: _text),
            ),
            Text(
              DocuTrackerMemoLayout.province,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: _text,
              ),
            ),
            Text(
              DocuTrackerMemoLayout.municipality,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: DocuTrackerMemoLayout.municipalityRed,
              ),
            ),
            Text(
              DocuTrackerMemoLayout.office,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: DocuTrackerMemoLayout.navy,
              ),
            ),
          ],
        ),
      ),
      Positioned.fromRect(
        key: const ValueKey('memo-logo-asenso'),
        rect: _rect(DocuTrackerMemoLayout.asensoLogo),
        child: asset(DocuTrackerMemoLayout.asensoLogoAsset),
      ),
      Positioned.fromRect(
        key: const ValueKey('memo-logo-bagong-pilipinas'),
        rect: _rect(DocuTrackerMemoLayout.bagongPilipinasLogo),
        child: asset(DocuTrackerMemoLayout.bagongPilipinasLogoAsset),
      ),
      Positioned.fromRect(
        rect: peach,
        child: const DecoratedBox(
          key: ValueKey('memo-peach-band'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [DocuTrackerMemoLayout.peach, Color(0x00FFFFFF)],
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _footer() => [
    Positioned.fromRect(
      key: const ValueKey('memo-footer'),
      rect: _rect(DocuTrackerMemoLayout.footerStrip),
      child: Image.asset(
        DocuTrackerMemoLayout.footerStripAsset,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) =>
            const ColoredBox(color: DocuTrackerMemoLayout.reservedArtwork),
      ),
    ),
    Positioned.fromRect(
      rect: _rect(DocuTrackerMemoLayout.sloganBar),
      child: const ColoredBox(
        color: DocuTrackerMemoLayout.sloganBand,
        child: Center(
          child: Text(
            DocuTrackerMemoLayout.slogan,
            key: ValueKey('memo-slogan'),
            maxLines: 1,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
            ),
          ),
        ),
      ),
    ),
  ];

  Widget _metadataRow(
    String label,
    TextEditingController controller, {
    required Key key,
    required String hint,
    required int maxLines,
    required int maxLength,
  }) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: DocuTrackerMemoLayout.metadataRowGap,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: DocuTrackerMemoLayout.metadataLabelWidth,
            child: Text(
              label,
              key: ValueKey('memo-label-${label.toLowerCase()}'),
            ),
          ),
          const SizedBox(
            width: DocuTrackerMemoLayout.metadataColonWidth,
            child: Text(':'),
          ),
          Expanded(
            child: _value(
              controller,
              key: key,
              hint: hint,
              maxLines: maxLines,
              maxLength: maxLength,
            ),
          ),
        ],
      ),
    );
  }

  Widget _value(
    TextEditingController controller, {
    required Key key,
    required String hint,
    required int maxLines,
    required int maxLength,
    double fontSize = DocuTrackerMemoLayout.metadataFontSize,
  }) {
    final style = TextStyle(
      fontFamily: DocuTrackerMemoLayout.fontFamily,
      fontSize: fontSize,
      color: _text,
    );
    if (!editable) {
      return Text(
        controller.text,
        key: key,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return TextField(
      key: key,
      controller: controller,
      style: style,
      minLines: 1,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: maxLines > 1 ? TextInputType.multiline : TextInputType.text,
      decoration: InputDecoration.collapsed(
        hintText: hint,
        hintStyle: style.copyWith(color: const Color(0xFF9CA3AF)),
      ).copyWith(counterText: ''),
    );
  }
}

class _SignatoryBlock extends StatelessWidget {
  const _SignatoryBlock({required this.signatory, required this.onSign});

  final DocuTrackerMemoSignatory signatory;
  final ValueChanged<DocuTrackerSignatureField>? onSign;

  @override
  Widget build(BuildContext context) {
    final field = signatory.field;
    final slot = signatory.slot.name;
    final onSign = this.onSign;
    final signable = field != null && field.canSign && onSign != null;
    final image = signatory.isSigned ? field?.signatureImageBytes : null;
    final name = signatory.printedName;
    final position = signatory.position;

    Widget area = image == null
        ? signable
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    border: Border.all(color: const Color(0xFFF59E0B)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.edit_rounded,
                          size: 16,
                          color: Color(0xFFB45309),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Click to sign',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.expand()
        : Image.memory(
            image,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const SizedBox.expand(),
          );
    area = KeyedSubtree(
      key: ValueKey('memo-signature-area-$slot'),
      child: area,
    );
    if (signable) {
      area = Semantics(
        button: true,
        label: '${DocuTrackerMemoSignatory.labelOf(signatory.slot)} signature',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSign(field),
            child: area,
          ),
        ),
      );
    }

    return Column(
      key: ValueKey('memo-signatory-$slot'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: area),
        Container(height: 1, color: _memoInk),
        const SizedBox(height: 2),
        Text(
          name ?? signatory.unassignedMessage,
          key: ValueKey('memo-signatory-name-$slot'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: name == null
              ? const TextStyle(
                  fontSize: DocuTrackerMemoLayout.signatoryPositionFontSize,
                  fontStyle: FontStyle.italic,
                  color: Color(0xFFB45309),
                )
              : const TextStyle(
                  fontSize: DocuTrackerMemoLayout.signatoryNameFontSize,
                  fontWeight: FontWeight.w700,
                  color: _memoInk,
                ),
        ),
        Text(
          position ?? '',
          key: ValueKey('memo-signatory-position-$slot'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: DocuTrackerMemoLayout.signatoryPositionFontSize,
            color: _memoInk,
          ),
        ),
      ],
    );
  }
}

class _ReleaseBlock extends StatelessWidget {
  const _ReleaseBlock({required this.release});

  final DocuTrackerMemoRelease release;

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF1D4ED8);
    const style = TextStyle(fontSize: 11.5, color: color);
    final remarks = release.remarks;
    return Container(
      key: const ValueKey('memo-release-block'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'RELEASED',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
              color: color,
            ),
          ),
          Text(
            'Released to: ${release.departmentName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
          Text(
            'Released by: ${release.releasedByName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
          Text(
            'Date: ${docuTrackerReleaseTimestamp(release.releasedAt)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
          if (remarks != null)
            Text(
              'Remarks: $remarks',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
        ],
      ),
    );
  }
}

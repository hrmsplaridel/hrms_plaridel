import 'package:hrms_plaridel/features/dtr/management/approvals/utils/workflow_print_layout.dart';
import 'package:hrms_plaridel/features/dtr/leave/models/leave_type_definition.dart';
import 'dart:typed_data';
import 'dart:convert';
import '../../../models/locator_print_layout.dart';
import '../../../models/locator_request_type.dart';
import '../../../utils/locator_layout_pdf.dart';
import '../../../utils/locator_form_signatories.dart';
import 'locator_print_layout_editor.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hrms_plaridel/core/api/client.dart';
import 'package:hrms_plaridel/core/widgets/form_pdf_preview.dart';
import 'package:hrms_plaridel/features/dtr/locator/utils/locator_slip_print.dart';

class LocatorPrintDraft {
  const LocatorPrintDraft({this.file,this.layout,this.layoutChanged=false,this.removeBackground=false});
  final PlatformFile? file;
  final LocatorPrintLayout? layout;
  final bool layoutChanged,removeBackground;
  bool get hasChanges=>file!=null||layoutChanged||removeBackground;
  Future<void> save(String typeId, {bool removeBackground = false}) async {
    await ApiClient.instance.post(
      '/api/locator-slips/print/types/$typeId',
      data: FormData.fromMap({
        'remove_background': (removeBackground||this.removeBackground).toString(),
        if(layoutChanged) 'print_layout': jsonEncode(layout?.toJson()),
        if (file != null)
          'file': MultipartFile.fromBytes(
            file!.bytes!,
            filename: file!.name,
            contentType: DioMediaType.parse(
              file!.extension?.toLowerCase() == 'pdf'
                  ? 'application/pdf'
                  : file!.extension?.toLowerCase() == 'png'
                  ? 'image/png'
                  : 'image/jpeg',
            ),
          ),
      }),
    );
  }
}

class LocatorPrintSettings extends StatefulWidget {
  const LocatorPrintSettings({
    super.key,
    this.typeId,
    this.initialDraft,
    this.onChanged,
    this.onSaved,
    this.enabled = true,
    this.readRequestType,
    this.readWorkflowSteps,
    this.onCustomFieldsChanged,
  });
  final String? typeId;
  final LocatorPrintDraft? initialDraft;
  final ValueChanged<LocatorPrintDraft>? onChanged;
  final VoidCallback? onSaved;
  final bool enabled;
  final LocatorRequestType Function()? readRequestType;
  final List<dynamic>? Function()? readWorkflowSteps;
  final ValueChanged<List<LeaveCustomFieldDefinition>>? onCustomFieldsChanged;
  @override
  State<LocatorPrintSettings> createState() => _LocatorPrintSettingsState();
}

class _LocatorPrintSettingsState extends State<LocatorPrintSettings> {
  PlatformFile? _file;
  String? _background, _error;
  bool _loading = false, _busy = false, _remove = false;
  LocatorPrintLayout? _layout;
  bool _layoutChanged=false, _schemaNeedsSave=false;
  bool get _disabled => _busy || !widget.enabled;
  @override
  void initState() {
    super.initState();
    _file = widget.initialDraft?.file;
    _layout=widget.initialDraft?.layout;
    _layoutChanged=widget.initialDraft?.layoutChanged??false;
    _remove=widget.initialDraft?.removeBackground??false;
    if (widget.typeId != null) _load();
  }

  void _changed() => widget.onChanged?.call(LocatorPrintDraft(file:_file,layout:_layout,layoutChanged:_layoutChanged,removeBackground:_remove));
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ApiClient.instance.get<Map<String, dynamic>>(
        '/api/locator-slips/print/types/${widget.typeId}',
      );
      if (mounted) {
        setState(() {
          _background = r.data?['background_name']?.toString();
          if(!_layoutChanged)_layout=r.data?['print_layout'] is Map?LocatorPrintLayout.fromJson(Map<String,dynamic>.from(r.data!['print_layout'] as Map)):null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load print settings. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
        withData: true,
      );
      if (!mounted || result == null) return;
      final file = result.files.single;
      if (file.size > 5242880 || file.bytes == null) {
        setState(() => _error = 'Select a readable file up to 5 MB.');
        return;
      }
      setState(() {
        _file = file;
        _remove = false;
        _error = null;
      });
      _changed();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not read the selected file. Please retry.',
        );
      }
    }
  }

  Future<void> _save() async {
    if (_schemaNeedsSave) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await LocatorPrintDraft(
        file: _file,
        layout:_layout,layoutChanged:_layoutChanged,
      ).save(widget.typeId!, removeBackground: _remove);
      if (!mounted) return;
      setState(() {
        _file = null;
        _remove = false;
        _layoutChanged=false;
      });
      widget.onSaved?.call();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Print settings saved. Filed locators retain their original template.',
            ),
          ),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(
          () => _error =
              (e.response?.data is Map ? e.response?.data['error'] : null)
                  ?.toString() ??
              'Could not save print settings.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save print settings.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if(_layout!=null || _layoutChanged || widget.typeId==null || _file!=null || _remove){
        await _previewDraft(_layout);
        return;
      }
      final bytes = await LocatorSlipPrint.buildPdf(
        id: null,
        employeeName: 'Sample Employee',
        dateText: 'Oct 10, 2026',
        requestTypeLabel: 'Locator / Official Business',
        locationLabel: 'Office / Destination',
        office: 'Municipal Hall',
        remarks: 'Official transaction',
        amIn: true,
        amOut: true,
        pmIn: true,
        pmOut: true,
      );
      final r = await ApiClient.instance.post<List<int>>(
        '/api/locator-slips/print/types/${widget.typeId}/preview',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: 'preview.pdf'),
        }),
        options: Options(responseType: ResponseType.bytes),
      );
      if (mounted) {
        await showFormPdfPreview(
          context: context,
          bytes: Uint8List.fromList(r.data!),
          title: 'Locator Form Preview',
          filename: 'Locator_Form_Sample.pdf',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not preview the saved form.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<dynamic>? get _workflowSteps => widget.readWorkflowSteps?.call();
  LocatorPrintedSignatory _sampleSignatory(String source) {
    final caption = workflowPrintCaption(_workflowSteps, source);
    return caption == null ? locatorLayoutSampleSignatory(_requestType, source)
        : LocatorPrintedSignatory(name: 'Sample signer', positionTitle: caption);
  }
  PrintLayoutEditorBindings? _bindings(LocatorRequestType type) {
    final signatures = workflowPrintSignatures(_workflowSteps);
    if (signatures.isEmpty) return null;
    return PrintLayoutEditorBindings(
      fields: {'employee_name':'Employee name','date':'Date','request_type':'Request type',
        'office':type.locationLabel,'reason':'Remarks / Reasons','time_segments':'DTR slots'},
      signatures: signatures, sample: locatorLayoutSample(type),
      defaultLayout: (orientation) => workflowPrintLayoutDefaults(
        LocatorPrintLayout.defaults(type, orientation: orientation), _workflowSteps),
      sampleSignatory: _sampleSignatory,
    );
  }
  LocatorRequestType get _requestType=>widget.readRequestType?.call()??LocatorRequestType.locator;
  DioMediaType _fileType(PlatformFile file)=>DioMediaType.parse(file.extension?.toLowerCase()=='pdf'?'application/pdf':file.extension?.toLowerCase()=='png'?'image/png':'image/jpeg');
  Future<void> _previewDraft(LocatorPrintLayout? layout, {List<LeaveCustomFieldDefinition>? customFields})async{
    final type=customFields==null?_requestType:_requestType.copyWith(employeeDetailSchema:customFields);
    final bytes=layout!=null?await buildLocatorLayoutPdf(layout:layout,form:locatorLayoutSample(type),signatories:LocatorFormSignatories(
      applicant:_sampleSignatory('applicant'),departmentHead:_sampleSignatory('department_head'),finalApprover:_sampleSignatory('hr_approver'),
      workflowApprovers: {for (final source in workflowPrintSignatures(_workflowSteps).keys) if(source.startsWith('workflow_step_')) source: _sampleSignatory(source)},
    )):await LocatorSlipPrint.buildPdf(id:null,employeeName:'Sample Employee',dateText:'Oct 13, 2026',requestTypeLabel:type.label,locationLabel:type.locationLabel,office:'Municipal Hall',remarks:'Sample purpose',amIn:true,amOut:true,pmIn:true,pmOut:true,
      signatories:LocatorFormSignatories(form:locatorLayoutSample(type)));
    final response=await ApiClient.instance.post<List<int>>('/api/locator-slips/print/preview',data:FormData.fromMap({
      if(widget.typeId!=null)'type_id':widget.typeId,
      'print_layout':jsonEncode(layout?.toJson()),'remove_background':_remove.toString(),
      'file':MultipartFile.fromBytes(bytes,filename:'preview.pdf'),
      if(_file!=null)'background':MultipartFile.fromBytes(_file!.bytes!,filename:_file!.name,contentType:_fileType(_file!)),
    }),options:Options(responseType:ResponseType.bytes));
    if(mounted)await showFormPdfPreview(context:context,bytes:Uint8List.fromList(response.data!),title:'Printed Form Preview',filename:'Locator_Form_Sample.pdf');
  }
  Future<void> _editLayout()async{
    if (_layout == null && widget.readWorkflowSteps != null && _workflowSteps?.isNotEmpty != true) {
      setState(() => _error = 'Select a workflow and wait for it to load before designing a new layout.');
      return;
    }
    setState((){_busy=true;_error=null;});
    try{
      Uint8List? pdf,image;
      if(_file!=null){if(_file!.extension?.toLowerCase()=='pdf'){pdf=_file!.bytes;}else{image=_file!.bytes;}}
      else if(!_remove && _background!=null && widget.typeId!=null){
        final response=await ApiClient.instance.get<List<int>>('/api/locator-slips/print/types/${widget.typeId}/background',options:Options(responseType:ResponseType.bytes));
        pdf=Uint8List.fromList(response.data!);
      }
      if(!mounted)return;
      final result=await showDialog<LocatorPrintLayout>(context:context,builder:(_)=>LocatorPrintLayoutEditor(
        requestType:_requestType,bindings:_bindings(_requestType),initialLayout:_layout,backgroundPdf:pdf,backgroundImage:image,onPreview:_previewDraft,
        onPreviewWithFields:(layout,fields)=>_previewDraft(layout,customFields:fields),
        onCustomFieldsChanged:widget.onCustomFieldsChanged==null?null:(fields){
          widget.onCustomFieldsChanged!(fields);
          setState(()=>_schemaNeedsSave=true);
        },
      ));
      if(result!=null && mounted){setState((){_layout=result;_layoutChanged=true;});_changed();}
    }catch(_){if(mounted)setState(()=>_error='Could not open the layout editor. Please retry.');}
    finally{if(mounted)setState(()=>_busy=false);}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LinearProgressIndicator();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Printed Form',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        Text(
          _remove
              ? 'Background will be removed'
              : _file?.name ?? _background ?? 'No background uploaded',
        ),
        const Text(
          'A4, Letter, Long Bond or Legal · portrait or landscape · PDF, PNG or JPEG · up to 5 MB',
        ),
        if (_schemaNeedsSave) const Text('Save the type changes to keep the new fields and layout.'),
        const Text(
          'Design a page using the background, fields and signatures. Existing forms keep their saved template.',
        ),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            TextButton.icon(onPressed:_disabled?null:_editLayout,icon:const Icon(Icons.dashboard_customize_outlined),label:Text(_layout==null?'Design layout':'Edit layout')),
            if(_layout!=null)TextButton(onPressed:_disabled?null:(){setState((){_layout=_workflowSteps?.isNotEmpty == true ? workflowPrintLayoutDefaults(LocatorPrintLayout.defaults(_requestType),_workflowSteps):null;_layoutChanged=true;});_changed();},child:const Text('Use default layout')),
            TextButton(
              onPressed: _disabled ? null : _pick,
              child: const Text('Upload background'),
            ),
            if (_file != null || _background != null)
              TextButton(
                onPressed: _disabled
                    ? null
                    : () {
                        setState(() {
                          _file = null;
                          _remove = widget.typeId != null;
                        });
                        _changed();
                      },
                child: const Text('Remove background'),
              ),
            if (widget.typeId != null)
              FilledButton(
                onPressed: _disabled || _schemaNeedsSave ? null : _save,
                child: const Text('Save print settings'),
              ),
              TextButton(
                onPressed: _disabled ? null : _preview,
                child: Text(_layoutChanged||widget.typeId==null||_file!=null||_remove?'Preview layout':'Preview saved form'),
              ),
            if (widget.typeId != null && _error != null)
              TextButton(
                onPressed: _disabled ? null : _load,
                child: const Text('Retry'),
              ),
          ],
        ),
        if (widget.typeId == null)
          const Text(
            'The background and layout will be saved when you create the locator type.',
          ),
      ],
    );
  }
}

/// Document actions that can be permission-controlled (Step 4: Admin Privilege Management).
enum DocumentAction {
  view,
  create,
  submit,
  edit,
  download,
  delete,
  returnDoc,
  forward,
  approve,
  reject,
}

extension DocumentActionExtension on DocumentAction {
  String get value => name;

  String get displayName => switch (this) {
        DocumentAction.view => 'View',
        DocumentAction.create => 'Create',
        DocumentAction.submit => 'Submit',
        DocumentAction.edit => 'Edit',
        DocumentAction.download => 'Download',
        DocumentAction.delete => 'Delete',
        DocumentAction.returnDoc => 'Return',
        DocumentAction.forward => 'Forward',
        DocumentAction.approve => 'Approve',
        DocumentAction.reject => 'Reject',
      };
}

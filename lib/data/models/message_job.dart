import 'template_variable_data.dart';

class MessageJob {
  final TemplateVariableData data;
  final List<String> renderedMessages;

  const MessageJob({required this.data, required this.renderedMessages});
}

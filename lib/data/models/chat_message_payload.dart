import 'dart:typed_data';

class ChatMessageTypes {
  const ChatMessageTypes._();

  static const String text = 'texto';
  static const String image = 'imagem';
  static const String video = 'video';
  static const String document = 'documento';
  static const String audio = 'audio';
  static const String location = 'localizacao';

  static bool isMedia(String value) {
    return value == image ||
        value == video ||
        value == document ||
        value == audio;
  }
}

class ChatMessagePayload {
  const ChatMessagePayload({
    this.content = '',
    this.messageType = ChatMessageTypes.text,
    this.messageId = '',
    this.fileName = '',
    this.mimeType = '',
    this.fileSize = 0,
    this.fileBytes,
    this.mediaUrl = '',
    this.latitude,
    this.longitude,
    this.locationName = '',
    this.locationAddress = '',
  });

  factory ChatMessagePayload.fromMap(Map<String, dynamic> map) {
    final rawBytes = map['arquivo_dados'];
    Uint8List? fileBytes;
    if (rawBytes is Uint8List) {
      fileBytes = rawBytes;
    } else if (rawBytes is ByteBuffer) {
      fileBytes = rawBytes.asUint8List();
    }

    return ChatMessagePayload(
      content: (map['conteudo'] ?? '').toString(),
      messageType:
          (map['tipo_msg'] ?? ChatMessageTypes.text).toString().trim().isEmpty
          ? ChatMessageTypes.text
          : (map['tipo_msg'] ?? ChatMessageTypes.text).toString().trim(),
      messageId: (map['mensagem_id'] ?? '').toString(),
      fileName: (map['arquivo_nome'] ?? '').toString(),
      mimeType: (map['arquivo_mime'] ?? '').toString(),
      fileSize: _asInt(map['arquivo_tamanho']),
      fileBytes: fileBytes,
      mediaUrl: (map['media_url'] ?? '').toString(),
      latitude: _asDouble(map['latitude']),
      longitude: _asDouble(map['longitude']),
      locationName: (map['local_nome'] ?? '').toString(),
      locationAddress: (map['local_endereco'] ?? '').toString(),
    );
  }

  final String content;
  final String messageType;
  final String messageId;
  final String fileName;
  final String mimeType;
  final int fileSize;
  final Uint8List? fileBytes;
  final String mediaUrl;
  final double? latitude;
  final double? longitude;
  final String locationName;
  final String locationAddress;

  bool get isText => messageType == ChatMessageTypes.text;
  bool get isImage => messageType == ChatMessageTypes.image;
  bool get isVideo => messageType == ChatMessageTypes.video;
  bool get isDocument => messageType == ChatMessageTypes.document;
  bool get isAudio => messageType == ChatMessageTypes.audio;
  bool get isLocation => messageType == ChatMessageTypes.location;
  bool get isMedia => ChatMessageTypes.isMedia(messageType);
  bool get hasFileBytes => fileBytes != null && fileBytes!.isNotEmpty;
  bool get hasLocation => latitude != null && longitude != null;

  bool get hasUserCaption {
    return content.trim().isNotEmpty;
  }

  String get previewText {
    final trimmed = content.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }

    if (isImage) return 'Imagem';
    if (isVideo) return 'Video';
    if (isDocument) {
      final name = fileName.trim();
      return name.isNotEmpty ? 'Documento: $name' : 'Documento';
    }
    if (isAudio) return 'Audio';
    if (isLocation) {
      final name = locationName.trim();
      if (name.isNotEmpty) {
        return name;
      }
      return 'Localizacao compartilhada';
    }

    return '';
  }

  ChatMessagePayload copyWith({
    String? content,
    String? messageType,
    String? messageId,
    String? fileName,
    String? mimeType,
    int? fileSize,
    Uint8List? fileBytes,
    String? mediaUrl,
    double? latitude,
    double? longitude,
    String? locationName,
    String? locationAddress,
  }) {
    return ChatMessagePayload(
      content: content ?? this.content,
      messageType: messageType ?? this.messageType,
      messageId: messageId ?? this.messageId,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      fileSize: fileSize ?? this.fileSize,
      fileBytes: fileBytes ?? this.fileBytes,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationName: locationName ?? this.locationName,
      locationAddress: locationAddress ?? this.locationAddress,
    );
  }

  static double? _asDouble(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }

    final normalized = value?.toString().trim().replaceAll(',', '.');
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return double.tryParse(normalized);
  }

  static int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

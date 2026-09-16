final class PageRange {
  PageRange({required this.startPage, int? endPage})
      : endPage = endPage ?? startPage {
    if (startPage < 1) {
      throw RangeError.range(startPage, 1, null, 'startPage');
    }
    if (this.endPage < startPage) {
      throw RangeError('endPage must be greater than or equal to startPage');
    }
  }

  final int startPage;
  final int endPage;

  bool contains(int pageNumber) =>
      pageNumber >= startPage && pageNumber <= endPage;

  int get length => endPage - startPage + 1;

  Map<String, Object?> toJson() => {
        'startPage': startPage,
        'endPage': endPage,
      };

  factory PageRange.fromJson(Map<String, Object?> json) => PageRange(
        startPage: json['startPage']! as int,
        endPage: json['endPage']! as int,
      );
}

final class DocumentRect {
  DocumentRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  }) {
    final values = [left, top, width, height];
    if (values.any((value) => !value.isFinite)) {
      throw const FormatException('DocumentRect values must be finite');
    }
    if (left < 0 || top < 0 || width < 0 || height < 0) {
      throw const FormatException('DocumentRect values must be non-negative');
    }
    if (left > 1 || top > 1 || left + width > 1 || top + height > 1) {
      throw const FormatException('DocumentRect must use normalized 0..1 coordinates');
    }
  }

  final double left;
  final double top;
  final double width;
  final double height;

  Map<String, Object?> toJson() => {
        'left': left,
        'top': top,
        'width': width,
        'height': height,
      };

  factory DocumentRect.fromJson(Map<String, Object?> json) => DocumentRect(
        left: (json['left']! as num).toDouble(),
        top: (json['top']! as num).toDouble(),
        width: (json['width']! as num).toDouble(),
        height: (json['height']! as num).toDouble(),
      );
}

final class DocumentTextBlock {
  DocumentTextBlock({
    required String text,
    this.bounds,
    this.confidence,
    this.language,
  }) : text = text.trim() {
    if (this.text.isEmpty) {
      throw const FormatException('Document text block cannot be empty');
    }
    final confidence = this.confidence;
    if (confidence != null &&
        (!confidence.isFinite || confidence < 0 || confidence > 1)) {
      throw const FormatException('confidence must be between 0 and 1');
    }
  }

  final String text;
  final DocumentRect? bounds;
  final double? confidence;
  final String? language;

  Map<String, Object?> toJson() => {
        'text': text,
        if (bounds != null) 'bounds': bounds!.toJson(),
        if (confidence != null) 'confidence': confidence,
        if (language != null) 'language': language,
      };

  factory DocumentTextBlock.fromJson(Map<String, Object?> json) =>
      DocumentTextBlock(
        text: json['text']! as String,
        bounds: switch (json['bounds']) {
          final Map value =>
            DocumentRect.fromJson(Map<String, Object?>.from(value)),
          _ => null,
        },
        confidence: switch (json['confidence']) {
          final num value => value.toDouble(),
          _ => null,
        },
        language: json['language'] as String?,
      );
}

final class ExtractedPage {
  ExtractedPage({
    required this.pageNumber,
    required this.text,
    Iterable<DocumentTextBlock> blocks = const [],
  }) : blocks = List.unmodifiable(blocks) {
    if (pageNumber < 1) {
      throw RangeError.range(pageNumber, 1, null, 'pageNumber');
    }
  }

  final int pageNumber;
  final String text;
  final List<DocumentTextBlock> blocks;

  Map<String, Object?> toJson() => {
        'pageNumber': pageNumber,
        'text': text,
        'blocks': [for (final block in blocks) block.toJson()],
      };

  factory ExtractedPage.fromJson(Map<String, Object?> json) => ExtractedPage(
        pageNumber: json['pageNumber']! as int,
        text: json['text']! as String,
        blocks: [
          for (final value in (json['blocks'] as List?) ?? const [])
            DocumentTextBlock.fromJson(
              Map<String, Object?>.from(value as Map),
            ),
        ],
      );
}

final class ExtractedDocument {
  ExtractedDocument({
    required String assetId,
    required String mimeType,
    required String providerId,
    required DateTime extractedAt,
    required Iterable<ExtractedPage> pages,
    Map<String, Object?> metadata = const {},
  })  : assetId = assetId.trim(),
        mimeType = mimeType.trim().toLowerCase(),
        providerId = providerId.trim(),
        extractedAt = extractedAt.toUtc(),
        pages = _normalizedPages(pages),
        metadata = Map.unmodifiable(metadata) {
    if (this.assetId.isEmpty) {
      throw const FormatException('assetId cannot be empty');
    }
    if (this.mimeType.isEmpty) {
      throw const FormatException('mimeType cannot be empty');
    }
    if (this.providerId.isEmpty) {
      throw const FormatException('providerId cannot be empty');
    }
  }

  final String assetId;
  final String mimeType;
  final String providerId;
  final DateTime extractedAt;
  final List<ExtractedPage> pages;
  final Map<String, Object?> metadata;

  String get plainText => pages
      .map((page) => page.text.trim())
      .where((text) => text.isNotEmpty)
      .join('\n\n');

  Map<String, Object?> toJson() => {
        'schemaVersion': 1,
        'assetId': assetId,
        'mimeType': mimeType,
        'providerId': providerId,
        'extractedAt': extractedAt.toIso8601String(),
        'pages': [for (final page in pages) page.toJson()],
        'metadata': metadata,
      };

  factory ExtractedDocument.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'] as int? ?? 1;
    if (version != 1) {
      throw FormatException('Unsupported extracted document schema: $version');
    }
    return ExtractedDocument(
      assetId: json['assetId']! as String,
      mimeType: json['mimeType']! as String,
      providerId: json['providerId']! as String,
      extractedAt: DateTime.parse(json['extractedAt']! as String),
      pages: [
        for (final value in (json['pages'] as List?) ?? const [])
          ExtractedPage.fromJson(Map<String, Object?>.from(value as Map)),
      ],
      metadata: Map<String, Object?>.from(
        (json['metadata'] as Map?) ?? const <String, Object?>{},
      ),
    );
  }

  static List<ExtractedPage> _normalizedPages(
    Iterable<ExtractedPage> source,
  ) {
    final pages = source.toList(growable: false)
      ..sort((left, right) => left.pageNumber.compareTo(right.pageNumber));
    for (var index = 1; index < pages.length; index++) {
      if (pages[index - 1].pageNumber == pages[index].pageNumber) {
        throw FormatException(
          'Duplicate extracted page number: ${pages[index].pageNumber}',
        );
      }
    }
    return List.unmodifiable(pages);
  }
}

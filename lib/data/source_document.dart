import 'package:objectbox/objectbox.dart';

/// Ingestion lifecycle status values. Stored as string in ObjectBox.
enum IngestionStatus {
  queued,
  processing,
  ready,
  failed;
}

/// ObjectBox entity: document metadata + ingestion lifecycle status.
@Entity()
class SourceDocument {
  @Id()
  int id = 0;

  @Unique() // prevents duplicate ingestion
  String documentId = ''; // SHA-256(bytes).substring(0, 16)

  String name = ''; // original filename
  String fileType = ''; // 'pdf' or 'txt'
  int totalChunks = 0; // set after ingestion completes
  int fileSizeBytes = 0;
  String status = 'queued'; // see IngestionStatus enum / State Machine in spec §5
  String createdAt = '';
  String updatedAt = '';

  SourceDocument();
}

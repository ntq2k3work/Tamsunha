import '../../../core/network/api_client.dart';

import '../../../core/domain/model_parsing.dart';
import '../../../core/domain/note_detail.dart';
import '../../../core/domain/note_tile.dart';
import '../../../core/domain/paper_color.dart';
import '../../../core/domain/placement_result.dart';
import '../../../core/domain/world_cell.dart';
import '../../../core/errors/backend_exception.dart';
import '../domain/wall_repository.dart';

final class ApiWallRepository implements WallRepository {
  const ApiWallRepository(this._client);

  final ApiClient? _client;

  ApiClient _requireClient() {
    final client = _client;
    if (client == null) throw BackendException.notConfigured();
    if (!client.session.hasSession) {
      throw const BackendException(
        code: 'UNAUTHENTICATED',
        message: 'Hãy đăng nhập để tiếp tục.',
      );
    }
    return client;
  }

  Future<Map<String, Object?>> _rpc(
    String name, {
    Map<String, Object?>? params,
  }) async {
    try {
      return await _requireClient().rpc(name, params: params);
    } on BackendException {
      rethrow;
    } catch (_) {
      throw BackendException.unavailable();
    }
  }

  @override
  Future<NoteDetail> getNoteDetail(String noteId) async {
    final data = await _rpc('get_note_detail', params: <String, Object?>{
      'p_note_id': noteId,
    });
    return NoteDetail.fromJson(data);
  }

  @override
  Future<WallTilePage> getWallTiles({
    required int minCellX,
    required int maxCellX,
    required int minCellY,
    required int maxCellY,
    WallTileCursor? cursor,
    int limit = 200,
  }) async {
    final data = await _rpc('get_wall_tiles', params: <String, Object?>{
      'p_min_cell_x': minCellX,
      'p_max_cell_x': maxCellX,
      'p_min_cell_y': minCellY,
      'p_max_cell_y': maxCellY,
      'p_cursor_cell_y': cursor?.cellY,
      'p_cursor_cell_x': cursor?.cellX,
      'p_cursor_id': cursor?.id,
      'p_limit': limit,
    });
    final rawItems = data['items'];
    if (rawItems is! List) throw BackendException.unavailable();
    final rawCursor = data['next_cursor'];
    final rawRevision = data['revision'];
    if (rawRevision is! int) throw BackendException.unavailable();
    return WallTilePage(
      items: rawItems
          .map((item) => NoteTile.fromJson(_asObjectMap(item)))
          .toList(growable: false),
      revision: rawRevision,
      nextCursor: rawCursor == null
          ? null
          : WallTileCursor(
              cellY: ModelParsing.requiredInt(_asObjectMap(rawCursor), 'cell_y'),
              cellX: ModelParsing.requiredInt(_asObjectMap(rawCursor), 'cell_x'),
              id: ModelParsing.requiredString(_asObjectMap(rawCursor), 'id'),
            ),
    );
  }

  @override
  Future<DiscoveryTarget> getDiscoveryTarget({
    List<({int tileX, int tileY})> excludeRegions = const [],
  }) async {
    if (excludeRegions.length > 10) {
      throw const BackendException(
        code: 'INVALID_INPUT',
        message: 'Không thể loại trừ quá 10 vùng cùng lúc.',
      );
    }
    final data = await _rpc('get_discovery_target', params: <String, Object?>{
      'p_exclude_regions': excludeRegions
          .map((region) => <String, int>{
                'tile_x': region.tileX,
                'tile_y': region.tileY,
              })
          .toList(growable: false),
    });
    return DiscoveryTarget(
      tileX: ModelParsing.requiredInt(data, 'tile_x'),
      tileY: ModelParsing.requiredInt(data, 'tile_y'),
      cameraWorldX: ModelParsing.requiredInt(data, 'camera_world_x'),
      cameraWorldY: ModelParsing.requiredInt(data, 'camera_world_y'),
      availableCellsEstimate:
          ModelParsing.requiredInt(data, 'available_cells_estimate'),
    );
  }

  @override
  Future<PlacementResult> placeNote({
    required String content,
    required PaperColor paperColor,
    required bool allowChat,
    required WorldCell cell,
    required String clientRequestId,
  }) async {
    final data = await _rpc('place_note', params: <String, Object?>{
      'p_content': content,
      'p_paper_color': paperColor.wireValue,
      'p_allow_chat': allowChat,
      'p_cell_x': cell.x,
      'p_cell_y': cell.y,
      'p_client_request_id': clientRequestId,
    });
    return PlacementResult.fromJson(data);
  }

  @override
  Future<NoteEditResult> editNote({
    required String noteId,
    required String newContent,
    required String clientRequestId,
  }) async {
    final data = await _rpc('edit_note', params: <String, Object?>{
      'p_note_id': noteId,
      'p_new_content': newContent,
      'p_client_request_id': clientRequestId,
    });
    return NoteEditResult(
      id: ModelParsing.requiredString(data, 'id'),
      status: ModelParsing.requiredString(data, 'status'),
      content: ModelParsing.requiredString(data, 'content'),
      contentVersion: ModelParsing.requiredInt(data, 'content_version'),
    );
  }

  @override
  Future<MyNotesPage> getMyNotes({
    DateTime? cursorCreatedAt,
    String? cursorId,
    int limit = 20,
  }) async {
    if ((cursorCreatedAt == null) != (cursorId == null)) {
      throw const BackendException(
        code: 'INVALID_INPUT',
        message: 'Dấu trang của nhật ký chưa đầy đủ.',
      );
    }
    final data = await _rpc('get_my_notes', params: <String, Object?>{
      'p_cursor_created_at': cursorCreatedAt?.toUtc().toIso8601String(),
      'p_cursor_id': cursorId,
      'p_limit': limit,
    });
    final rawItems = data['items'];
    if (rawItems is! List) throw BackendException.unavailable();
    final items = rawItems.map((item) {
      final json = _asObjectMap(item);
      return MyNoteSummary(
        id: ModelParsing.requiredString(json, 'id'),
        content: ModelParsing.requiredString(json, 'content'),
        paperColor: PaperColor.fromJson(json['paper_color']),
        status: ModelParsing.requiredString(json, 'status'),
        cell: WorldCell.fromJson(json),
        createdAt: ModelParsing.requiredTimestamp(json, 'created_at'),
        allowChat: ModelParsing.requiredBool(json, 'allow_chat'),
        canEdit: ModelParsing.requiredBool(json, 'can_edit'),
        canDelete: ModelParsing.requiredBool(json, 'can_delete'),
      );
    }).toList(growable: false);
    final rawCursor = data['next_cursor'];
    final cursor = rawCursor == null ? null : _asObjectMap(rawCursor);
    return MyNotesPage(
      items: items,
      dailyQuotaUsed: ModelParsing.requiredBool(data, 'daily_quota_used'),
      nextCursorCreatedAt: cursor == null
          ? null
          : ModelParsing.requiredTimestamp(cursor, 'created_at'),
      nextCursorId: cursor == null
          ? null
          : ModelParsing.requiredString(cursor, 'id'),
    );
  }

  @override
  Future<void> deleteNote(
    String noteId, {
    required String clientRequestId,
  }) async {
    await _rpc('delete_note', params: <String, Object?>{
      'p_note_id': noteId,
      'p_client_request_id': clientRequestId,
    });
  }

  @override
  Future<void> updateNoteChat(String noteId, {required bool allowChat}) async {
    await _rpc('update_note_chat', params: <String, Object?>{
      'p_note_id': noteId,
      'p_allow_chat': allowChat,
    });
  }

  Map<String, Object?> _asObjectMap(Object? value) {
    if (value is! Map) throw BackendException.unavailable();
    return Map<String, Object?>.from(value);
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:tuong_nho/core/domain/conversation.dart';
import 'package:tuong_nho/core/domain/message.dart';
import 'package:tuong_nho/core/domain/note_detail.dart';
import 'package:tuong_nho/core/domain/note_tile.dart';
import 'package:tuong_nho/core/domain/paper_color.dart';
import 'package:tuong_nho/core/domain/placement_result.dart';
import 'package:tuong_nho/core/domain/wall_region.dart';
import 'package:tuong_nho/core/domain/world_cell.dart';

void main() {
  group('shared DTOs', () {
    test('NoteTile ignores private input fields and serializes only its public projection', () {
      final tile = NoteTile.fromJson(<String, Object?>{
        'id': 'note-1',
        'cell_x': -1,
        'cell_y': 8,
        'paper_color': 'sage',
        'style_seed': 42,
        'published_at': '2026-10-23T10:00:00Z',
        'content': 'must not enter the tile DTO',
        'author_id': 'private-user-id',
      });

      expect(tile.cell, const WorldCell(x: -1, y: 8));
      expect(tile.toJson().keys, containsAll(<String>[
        'id', 'cell_x', 'cell_y', 'paper_color', 'style_seed', 'published_at',
      ]));
      expect(tile.toJson(), isNot(contains('content')));
      expect(tile.toJson(), isNot(contains('author_id')));
    });

    test('NoteDetail round-trips reader state without any author identifier', () {
      final detail = NoteDetail.fromJson(<String, Object?>{
        'id': 'note-2',
        'content': 'A quiet thought.',
        'paper_color': 'butter',
        'published_at': null,
        'status': 'pending_review',
        'can_encourage': false,
        'already_encouraged': false,
        'can_start_chat': false,
        'is_owner': true,
        'allow_chat': true,
        'can_edit': true,
        'can_delete': true,
        'author_id': 'private-user-id',
      });

      expect(detail.publishedAt, isNull);
      expect(detail.status, 'pending_review');
      expect(detail.toJson()['author_id'], isNull);
      expect(NoteDetail.fromJson(detail.toJson()).content, detail.content);
    });

    test('Conversation rejects inconsistent outbound state and preserves safe status', () {
      expect(
        () => Conversation(
          id: 'conversation-1',
          created: false,
          canSend: true,
          remainingOutbound: 0,
        ),
        throwsArgumentError,
      );
      final conversation = Conversation.fromJson(<String, Object?>{
        'conversation_id': 'conversation-1',
        'created': true,
        'can_send': false,
        'remaining_outbound': 0,
        'status': 'blocked',
      });
      expect(conversation.isClosed, isTrue);
      expect(conversation.toJson()['status'], 'blocked');
    });

    test('Message round-trips delivery state without participant IDs', () {
      final message = Message.fromJson(<String, Object?>{
        'id': 'message-1',
        'conversation_id': 'conversation-1',
        'body': 'Hello.',
        'is_mine': true,
        'created_at': '2026-10-23T10:00:00Z',
        'status': 'pending_review',
        'sender_id': 'private-user-id',
      });
      expect(message.status, 'pending_review');
      expect(message.toJson(), isNot(contains('sender_id')));
    });

    test('placement rejects unsupported statuses and region validates estimates', () {
      expect(
        () => PlacementResult.fromJson(<String, Object?>{
          'note_id': 'note-1',
          'status': 'unknown',
          'cell_x': 0,
          'cell_y': 0,
        }),
        throwsFormatException,
      );
      expect(
        () => WallRegion(tileX: 0, tileY: 0, availableCellsEstimate: 65),
        throwsArgumentError,
      );
      expect(() => PaperColor.fromJson('not-a-color'), throwsFormatException);
    });
  });
}

import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import '../../core/sync/workspace_repository.dart';
import 'photo_compression.dart';

class MemberPhotos {
  MemberPhotos(this.client, this.repository);
  final SupabaseClient client;
  final WorkspaceRepository repository;
  final Map<String, ({String url, DateTime expires})> _urls = {};
  Future<String> url(String path) async {
    final cached = _urls[path];
    if (cached != null && cached.expires.isAfter(DateTime.now())) {
      return cached.url;
    }
    final url = await client.storage
        .from('member-photos')
        .createSignedUrl(path, 300);
    _urls[path] = (
      url: url,
      expires: DateTime.now().add(const Duration(minutes: 4)),
    );
    return url;
  }

  Future<void> upload(CachedRecord member, Uint8List bytes) async {
    if (!repository.access.editMembers) throw StateError('Permission denied.');
    if (member.syncState != 'synced' || member.version == 0) {
      throw StateError('Sync this member before uploading a photo.');
    }
    final access = repository.access;
    final path =
        '${access.gymId}/${member.id}/${access.userId}/${const Uuid().v4()}.jpg';
    await client.storage
        .from('member-photos')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            cacheControl: '300',
          ),
        );
    // Retry the same operation after an uncertain response, preserving idempotency.
    final operation = const Uuid().v4();
    Map<String, dynamic>? result;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        result = Map<String, dynamic>.from(
          await client.rpc(
            'set_member_photo',
            params: {
              'p_gym': access.gymId,
              'p_member': member.id,
              'p_expected': member.version,
              'p_path': path,
              'p_operation': operation,
            },
          ) as Map,
        );
        break;
      } on PostgrestException {
        try {
          await client.storage.from('member-photos').remove([path]);
        } catch (_) {}
        rethrow;
      } catch (_) {
        if (attempt == 1) rethrow;
      }
    }
    final saved = result!;
    await repository.db.transaction(() async {
      final current =
          await (repository.db.select(repository.db.cachedRecords)..where(
                (r) =>
                    r.scope.equals(repository.scope) &
                    r.kind.equals('members') &
                    r.id.equals(member.id),
              ))
              .getSingleOrNull();
      final pending = current != null && current.syncState != 'synced';
      await repository.db
          .into(repository.db.cachedRecords)
          .insertOnConflictUpdate(
            CachedRecordsCompanion.insert(
              scope: repository.scope,
              kind: 'members',
              id: member.id,
              payload: jsonEncode(
                pending
                    ? {
                        ...jsonDecode(current.payload) as Map<String, dynamic>,
                        'profile_image': path,
                      }
                    : saved,
              ),
              version: Value(
                pending ? current.version : saved['version'] as int,
              ),
              syncState: Value(pending ? current.syncState : 'synced'),
            ),
          );
    });
    final old = (jsonDecode(member.payload) as Map)['profile_image'];
    if (old is String && old.isNotEmpty && old != path) {
      try {
        await client.storage.from('member-photos').remove([old]);
      } catch (_) {}
    }
  }
}

class MemberPhoto extends StatelessWidget {
  const MemberPhoto({
    super.key,
    required this.photos,
    required this.path,
    this.size = 44,
  });
  final MemberPhotos photos;
  final String? path;
  final double size;
  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: const Color(0xFFECE9FA),
      alignment: Alignment.center,
      child: Icon(Icons.person_outline, size: size * .55),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: size,
        height: size,
        child: path == null || path!.isEmpty
            ? placeholder
            : FutureBuilder<String>(
                future: photos.url(path!),
                builder: (context, snapshot) => snapshot.hasData
                    ? Image.network(
                        snapshot.data!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, error, stack) => placeholder,
                      )
                    : placeholder,
              ),
      ),
    );
  }
}

class MemberPhotoEditor extends StatefulWidget {
  const MemberPhotoEditor({
    super.key,
    required this.photos,
    required this.member,
  });
  final MemberPhotos photos;
  final CachedRecord member;
  @override
  State<MemberPhotoEditor> createState() => _MemberPhotoEditorState();
}

class _MemberPhotoEditorState extends State<MemberPhotoEditor> {
  bool busy = false;
  String? message;
  Future<void> choose(CachedRecord member) async {
    setState(() {
      busy = true;
      message = 'Choose a photo';
    });
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
        requestFullMetadata: false,
      );
      if (file == null) {
        if (mounted) setState(() => message = null);
        return;
      }
      if (await file.length() > 12 * 1024 * 1024) {
        throw const FormatException('Choose a photo smaller than 12 MB.');
      }
      if (mounted) setState(() => message = 'Optimizing photo…');
      final bytes = await compute(
        compressMemberPhoto,
        await file.readAsBytes(),
      );
      if (mounted) setState(() => message = 'Uploading photo…');
      await widget.photos.upload(member, bytes);
      if (mounted) {
        setState(
          () => message = 'Photo saved (${(bytes.length / 1024).ceil()} KB)',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => message = switch (error) {
            FormatException e => e.message,
            StateError e => e.message,
            PostgrestException e when e.code == '40001' =>
              'Member changed. Sync, reopen the details and retry.',
            _ => 'Photo could not be confirmed. Check your connection, sync and try again.',
          },
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CachedRecord>>(
    stream: widget.photos.repository.watch('members'),
    builder: (context, snapshot) {
      final member =
          snapshot.data?.where((r) => r.id == widget.member.id).firstOrNull ??
          widget.member;
      final path =
          (jsonDecode(member.payload) as Map)['profile_image'] as String?;
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MemberPhoto(photos: widget.photos, path: path, size: 112),
            if (widget.photos.repository.access.editMembers) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: busy ? null : () => choose(member),
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_a_photo_outlined),
                label: Text(
                  path == null || path.isEmpty
                      ? 'Add profile photo'
                      : 'Change profile photo',
                ),
              ),
              const Text(
                'Automatically compressed · up to 512px · maximum 150 KB',
                style: TextStyle(fontSize: 12),
              ),
              if (message != null) Text(message!),
            ],
          ],
        ),
      );
    },
  );
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'store.dart';

/// Gambar dari URL (Firebase Storage) atau path file lokal (mode demo).
Widget photoImage(String source, {BoxFit fit = BoxFit.cover}) {
  Widget error(BuildContext _, Object __, StackTrace? ___) =>
      const Center(child: Icon(Icons.broken_image_outlined));
  if (source.isEmpty) {
    return const Center(child: Icon(Icons.image_not_supported_outlined));
  }
  return source.startsWith('http')
      ? Image.network(source, fit: fit, errorBuilder: error)
      : Image.file(File(source), fit: fit, errorBuilder: error);
}

/// Pilih foto dari kamera atau galeri (dikompres agar unggahan ringan).
/// Mengembalikan null bila dibatalkan.
Future<XFile?> pickPhoto(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Ambil dari kamera'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Pilih dari galeri'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;
  try {
    // Dikompres agar unggahan ringan (< 5 MB, lihat storage.rules).
    return await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 75,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengambil foto: ${describeError(e)}')));
    }
    return null;
  }
}

class PhotoThumb extends StatelessWidget {
  const PhotoThumb({super.key, required this.source, this.onTap, this.size = 96});

  final String source;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size > 64 ? 12 : 8),
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: InkWell(onTap: onTap, child: photoImage(source)),
        ),
      ),
    );
  }
}

/// Deretan thumbnail; ketuk untuk membuka layar penuh.
class PhotoStrip extends StatelessWidget {
  const PhotoStrip({super.key, required this.photos, this.size = 96});

  final List<String> photos;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => PhotoThumb(
          source: photos[i],
          size: size,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PhotoViewer(photos: photos, initial: i),
          )),
        ),
      ),
    );
  }
}

/// Thumbnail foto yang baru dipilih, dengan tombol hapus.
class RemovablePhoto extends StatelessWidget {
  const RemovablePhoto({super.key, required this.source, this.onRemove});

  final String source;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PhotoThumb(source: source),
        Positioned(
          top: 2,
          right: 2,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tombol kotak "Tambah foto".
class AddPhotoButton extends StatelessWidget {
  const AddPhotoButton({super.key, required this.onPressed, this.label = 'Tambah'});

  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_a_photo_outlined),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class PhotoViewer extends StatelessWidget {
  const PhotoViewer({super.key, required this.photos, this.initial = 0});

  final List<String> photos;
  final int initial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: PageView.builder(
        controller: PageController(initialPage: initial),
        itemCount: photos.length,
        itemBuilder: (_, i) => InteractiveViewer(
          child: Center(child: photoImage(photos[i], fit: BoxFit.contain)),
        ),
      ),
    );
  }
}

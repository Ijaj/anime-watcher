import 'package:flutter/material.dart';

/// Network cover art with a placeholder when missing or offline.
class CoverImage extends StatelessWidget {
  final String? url;
  final double width;
  final double height;
  final double borderRadius;

  const CoverImage({super.key, required this.url, required this.width, required this.height, this.borderRadius = 8});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: width,
      height: height,
      color: Colors.white10,
      child: Icon(Icons.movie_outlined, size: width / 2, color: Colors.white38),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: url == null
          ? placeholder
          : Image.network(
              url!,
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder,
              frameBuilder: (_, child, frame, sync) => sync || frame != null ? child : placeholder,
            ),
    );
  }
}

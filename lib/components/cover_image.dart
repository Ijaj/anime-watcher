import 'dart:io';

import 'package:flutter/material.dart';

/// Cover art from the local cache ([path]) or the network ([url]), with a
/// placeholder when neither is available.
class CoverImage extends StatelessWidget {
  final String? path;
  final String? url;
  final double width;
  final double height;
  final double borderRadius;

  const CoverImage({
    super.key,
    this.path,
    required this.url,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: width,
      height: height,
      color: Colors.white10,
      child: Icon(Icons.movie_outlined, size: width / 2, color: Colors.white38),
    );
    final network = url == null
        ? placeholder
        : Image.network(
            url!,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => placeholder,
            frameBuilder: (_, child, frame, sync) => sync || frame != null ? child : placeholder,
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: path == null
          ? network
          : Image.file(
              File(path!),
              width: width,
              height: height,
              fit: BoxFit.cover,
              // The cached file may have been deleted; the network copy is next best.
              errorBuilder: (_, _, _) => network,
            ),
    );
  }
}

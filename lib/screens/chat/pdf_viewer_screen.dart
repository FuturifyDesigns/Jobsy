import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import '../../config/colors.dart';
import '../../utils/error_messages.dart';

/// Full-screen PDF viewer with pinch-zoom and page navigation.
/// Loads from a signed URL (same as image fullscreen).
class PdfViewerScreen extends StatelessWidget {
  final String url;
  final String filename;

  const PdfViewerScreen({
    super.key,
    required this.url,
    required this.filename,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          filename,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        elevation: 0,
      ),
      body: PdfViewer.uri(
        Uri.parse(url),
        params: PdfViewerParams(
          backgroundColor: Colors.black,
          loadingBannerBuilder: (context, bytesDownloaded, totalBytes) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                      value: totalBytes != null && totalBytes > 0
                          ? bytesDownloaded / totalBytes
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    totalBytes != null && totalBytes > 0
                        ? 'Loading ${((bytesDownloaded / totalBytes) * 100).toStringAsFixed(0)}%'
                        : 'Loading…',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            );
          },
          errorBannerBuilder: (context, error, stackTrace, documentRef) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.white70,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Could not open this PDF',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      friendlyErrorMessage(error),
                      maxLines: 3,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

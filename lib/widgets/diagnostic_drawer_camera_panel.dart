import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../services/microscope_capture_service.dart';

/// Live UVC preview + capture for the diagnostic end drawer (Linux: v4l2 / camera_desktop).
class DiagnosticDrawerCameraPanel extends StatefulWidget {
  const DiagnosticDrawerCameraPanel({
    super.key,
    required this.repairId,
    required this.enabled,
    required this.onCaptured,
  });

  final String repairId;
  final bool enabled;
  final Future<void> Function(String savedJpegPath) onCaptured;

  @override
  State<DiagnosticDrawerCameraPanel> createState() =>
      _DiagnosticDrawerCameraPanelState();
}

class _DiagnosticDrawerCameraPanelState
    extends State<DiagnosticDrawerCameraPanel> {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _cameraIndex = 0;
  String? _error;
  bool _ready = false;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _error = 'Podgląd kamery niedostępny w przeglądarce.';
      return;
    }
    _init();
  }

  Future<void> _init() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(
          () => _error =
              'Brak urządzenia wideo. Zamknij inne programy (np. guvcview) używające tej samej kamery.',
        );
        return;
      }
      await _openCamera(_cameraIndex);
    } on CameraException catch (e) {
      setState(() => _error = 'Kamera: ${e.description ?? e.code}');
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _openCamera(int index) async {
    await _controller?.dispose();
    _controller = null;
    if (!mounted) return;
    setState(() {
      _ready = false;
      _error = null;
    });

    final cam = _cameras[index];
    final controller = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _cameraIndex = index;
      _ready = true;
    });
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !_ready || _capturing || !widget.enabled) return;
    setState(() => _capturing = true);
    try {
      final shot = await c.takePicture();
      final dir = await getApplicationSupportDirectory();
      final sub =
          Directory(p.join(dir.path, 'microscope_captures', widget.repairId));
      await sub.create(recursive: true);
      final outPath = p.join(sub.path, '${Uuid().v4()}.jpg');
      var bytes = await shot.readAsBytes();
      bytes = MicroscopeCaptureService.ensureJpegUnderApiLimit(bytes);
      await File(outPath).writeAsBytes(bytes);
      if (!mounted) return;
      await widget.onCaptured(outPath);
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Przechwycenie nie powiodło się: ${e.description ?? e.code}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd zapisu: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          _error!,
          style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_cameras.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Text('Kamera: ', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: _cameraIndex,
                        style: const TextStyle(fontSize: 12),
                        items: [
                          for (var i = 0; i < _cameras.length; i++)
                            DropdownMenuItem(
                              value: i,
                              child: Text(
                                _cameras[i].name.isNotEmpty
                                    ? _cameras[i].name
                                    : 'Urządzenie $i',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _capturing || !_ready
                            ? null
                            : (v) {
                                if (v == null) return;
                                _openCamera(v);
                              },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(
            height: 200,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ColoredBox(
                color: Colors.black,
                child: _buildPreview(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: (_ready &&
                    !(_capturing) &&
                    widget.enabled)
                ? _capture
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            icon: _capturing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.camera_alt, size: 20),
            label: Text(_capturing ? 'Zapisywanie…' : 'Przechwyć obraz'),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final c = _controller;
    if (!_ready || c == null || !c.value.isInitialized) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: Colors.orange,
                strokeWidth: 2,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Podłączanie kamery…',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      );
    }
    return Center(
      child: CameraPreview(c),
    );
  }
}

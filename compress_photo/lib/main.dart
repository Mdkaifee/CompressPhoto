import 'dart:convert';
import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const CompressApp());
}

class CompressApp extends StatelessWidget {
  const CompressApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Compress Photo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const CompressHomePage(),
    );
  }
}

class CompressHomePage extends StatefulWidget {
  const CompressHomePage({super.key});

  @override
  State<CompressHomePage> createState() => _CompressHomePageState();
}

class _CompressHomePageState extends State<CompressHomePage> {
  final ImagePicker _picker = ImagePicker();

  XFile? _selectedFile;
  Uint8List? _selectedBytes;
  String? _selectedName;
  Uint8List? _compressedBytes;
  String? _savedPath;
  bool _isCompressing = false;
  String? _status;
  int _quality = 80;

  CompressFormat _detectTargetFormat() {
    final bytes = _selectedBytes;
    if (bytes != null) {
      // PNG signature: 89 50 4E 47 0D 0A 1A 0A
      if (bytes.length >= 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47 &&
          bytes[4] == 0x0D &&
          bytes[5] == 0x0A &&
          bytes[6] == 0x1A &&
          bytes[7] == 0x0A) {
        return CompressFormat.png;
      }

      // JPEG signature: FF D8
      if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
        return CompressFormat.jpeg;
      }
    }

    final name = (_selectedName ?? '').toLowerCase();
    if (name.endsWith('.png')) return CompressFormat.png;
    if (name.endsWith('.webp')) return CompressFormat.webp;
    return CompressFormat.jpeg;
  }

  void _log(String message) {
    final stamp = DateTime.now().toIso8601String();
    final line = '$stamp | $message';
    debugPrint(line);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }

  String _compressionRatio() {
    if (_selectedBytes == null || _compressedBytes == null) return '-';
    final original = _selectedBytes!.length;
    final compressed = _compressedBytes!.length;
    if (original == 0) return '-';
    final ratio = (1 - (compressed / original)) * 100;
    return '${ratio.toStringAsFixed(1)}%';
  }

  Future<void> _pickImage() async {
    setState(() {
      _status = null;
      _compressedBytes = null;
      _savedPath = null;
    });

    _log('Opening image picker');
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) {
      _log('Image picker canceled');
      return;
    }

    final bytes = await file.readAsBytes();
    final diskSize = await file.length();
    setState(() {
      _selectedFile = file;
      _selectedBytes = bytes;
      _selectedName = file.name;
    });
    final memMb = bytes.length / (1024 * 1024);
    final diskMb = diskSize / (1024 * 1024);
    _log(
      'Selected ${file.name} (read=${bytes.length} bytes, ${memMb.toStringAsFixed(2)} MB | '
      'disk=$diskSize bytes, ${diskMb.toStringAsFixed(2)} MB) path=${file.path}',
    );
  }

  Future<void> _compress() async {
    if (_selectedFile == null || _selectedBytes == null) {
      setState(() => _status = 'Please select an image first.');
      _log('Compress blocked: no image selected');
      return;
    }

    setState(() {
      _isCompressing = true;
      _status = 'Compressing...';
      _compressedBytes = null;
      _savedPath = null;
    });
    _log('Compressing locally with quality=$_quality');

    try {
      final targetFormat = _detectTargetFormat();
      final result = await FlutterImageCompress.compressWithFile(
        _selectedFile!.path,
        quality: _quality,
        format: targetFormat,
      );

      if (result == null) {
        setState(() => _status = 'Compression failed.');
        _log('Compression returned null');
        return;
      }

      setState(() {
        _compressedBytes = result;
        _status = 'Compressed.';
      });
      _log('Compression complete. Output size: ${result.length} bytes');
    } catch (error) {
      setState(() => _status = 'Error: $error');
      _log('Error during compression: $error');
    } finally {
      setState(() {
        _isCompressing = false;
      });
    }
  }

  Future<void> _saveCompressed() async {
    if (_compressedBytes == null) return;

    try {
      if (Platform.isAndroid) {
        final photos = await Permission.photos.request();
        final storage = await Permission.storage.request();
        if (!photos.isGranted && !storage.isGranted) {
          setState(() => _status = 'Permission denied.');
          _log('Storage/photos permission denied');
          return;
        }
      } else {
        final status = await Permission.photos.request();
        if (!status.isGranted) {
          setState(() => _status = 'Permission denied.');
          _log('Photo permission denied');
          return;
        }
      }

      final name = _selectedName ?? 'image.jpg';
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final result = await ImageGallerySaver.saveImage(
        _compressedBytes!,
        name: 'compressed_${stamp}_$name',
        quality: _quality,
      );

      final filePath = result['filePath']?.toString() ?? result['path']?.toString();
      setState(() => _savedPath = filePath);
      _log('Saved to gallery: $filePath');
      setState(() => _status = 'Saved to gallery.');
    } catch (error) {
      setState(() => _status = 'Save failed: $error');
      _log('Save failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _selectedBytes == null
        ? const SizedBox.shrink()
        : ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              _compressedBytes ?? _selectedBytes!,
              height: 220,
              fit: BoxFit.cover,
            ),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compress Photo'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PythonCompressPage()),
                );
              },
              icon: const Icon(Icons.cloud_outlined),
              label: const Text('Compress Using Python (Backend)'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isCompressing ? null : _pickImage,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Upload Photo'),
            ),
            const SizedBox(height: 12),
            Center(child: preview),
            const SizedBox(height: 16),
            Text(
              'Compression Quality',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('80%'),
                  selected: _quality == 80,
                  onSelected: _isCompressing
                      ? null
                      : (selected) {
                          if (selected) {
                            setState(() => _quality = 80);
                          }
                        },
                ),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('90%'),
                  selected: _quality == 90,
                  onSelected: _isCompressing
                      ? null
                      : (selected) {
                          if (selected) {
                            setState(() => _quality = 90);
                          }
                        },
                ),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('100%'),
                  selected: _quality == 100,
                  onSelected: _isCompressing
                      ? null
                      : (selected) {
                          if (selected) {
                            setState(() => _quality = 100);
                          }
                        },
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: (_selectedBytes == null || _isCompressing) ? null : _compress,
              child: _isCompressing
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Compress'),
            ),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(
                _status!,
                style: TextStyle(
                  color: _status!.startsWith('Error') || _status!.startsWith('Upload failed')
                      ? Colors.red
                      : Colors.green,
                ),
              ),
            ],
            if (_compressedBytes != null && _selectedBytes != null) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Original: ${_formatBytes(_selectedBytes!.length)}'),
                      Text('Compressed: ${_formatBytes(_compressedBytes!.length)}'),
                      Text('Quality: $_quality%'),
                      Text('Reduction: ${_compressionRatio()}'),
                    ],
                  ),
                ),
              ),
            ],
            if (_compressedBytes != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _saveCompressed,
                icon: const Icon(Icons.save_alt),
                label: const Text('Save Compressed'),
              ),
            ],
            if (_savedPath != null) ...[
              const SizedBox(height: 8),
              Text(
                'Saved: $_savedPath',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PythonCompressPage extends StatefulWidget {
  const PythonCompressPage({super.key});

  @override
  State<PythonCompressPage> createState() => _PythonCompressPageState();
}

class _PythonCompressPageState extends State<PythonCompressPage> {
  final ImagePicker _picker = ImagePicker();
  late final TextEditingController _baseUrlController;

  static const String _defaultNgrokBaseUrl =
      'https://embryonic-conoidally-radia.ngrok-free.dev';

  XFile? _selectedFile;
  Uint8List? _selectedBytes;
  String? _selectedName;
  Uint8List? _compressedBytes;
  String? _downloadUrl;
  bool _isCompressing = false;
  String? _status;
  int _quality = 80;
  String _format = 'auto';

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(text: _defaultBaseUrl());
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    super.dispose();
  }

  static String _defaultBaseUrl() {
    if (Platform.isAndroid) {
      // On real devices, prefer a tunnel like ngrok. `10.0.2.2` is emulator-only.
      return _defaultNgrokBaseUrl;
    }
    return 'http://127.0.0.1:8000';
  }

  void _log(String message) {
    final stamp = DateTime.now().toIso8601String();
    debugPrint('$stamp | PY | $message');
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }

  String _compressionRatio() {
    if (_selectedBytes == null || _compressedBytes == null) return '-';
    final original = _selectedBytes!.length;
    final compressed = _compressedBytes!.length;
    if (original == 0) return '-';
    final ratio = (1 - (compressed / original)) * 100;
    return '${ratio.toStringAsFixed(1)}%';
  }

  String _cleanBaseUrl(String input) {
    final cleaned = input.trim().replaceAll(RegExp(r'/+$'), '');
    return cleaned;
  }

  String _guessMimeType() {
    final name = (_selectedName ?? '').toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.avif')) return 'image/avif';
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';

    final bytes = _selectedBytes;
    if (bytes != null && bytes.length >= 12) {
      // PNG signature: 89 50 4E 47 0D 0A 1A 0A
      if (bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47 &&
          bytes[4] == 0x0D &&
          bytes[5] == 0x0A &&
          bytes[6] == 0x1A &&
          bytes[7] == 0x0A) {
        return 'image/png';
      }
      // JPEG signature: FF D8
      if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
        return 'image/jpeg';
      }
      // WEBP: "RIFF....WEBP"
      if (bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50) {
        return 'image/webp';
      }
    }
    return 'application/octet-stream';
  }

  Future<void> _pickImage() async {
    setState(() {
      _status = null;
      _compressedBytes = null;
      _downloadUrl = null;
    });

    _log('Opening image picker');
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) {
      _log('Image picker canceled');
      return;
    }

    final bytes = await file.readAsBytes();
    final diskSize = await file.length();
    setState(() {
      _selectedFile = file;
      _selectedBytes = bytes;
      _selectedName = file.name;
    });

    _log(
      'Selected ${file.name} (read=${bytes.length} bytes, disk=$diskSize bytes) path=${file.path}',
    );
  }

  Future<Uint8List> _downloadBytes(HttpClient client, Uri url) async {
    final request = await client.getUrl(url);
    request.headers.set('ngrok-skip-browser-warning', 'true');
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await utf8.decodeStream(response);
      throw Exception('Download failed (${response.statusCode}): $body');
    }
    return consolidateHttpClientResponseBytes(response);
  }

  Future<void> _compressWithPython() async {
    final file = _selectedFile;
    final bytes = _selectedBytes;
    if (file == null || bytes == null) {
      setState(() => _status = 'Please select an image first.');
      _log('Compress blocked: no image selected');
      return;
    }

    final baseUrl = _cleanBaseUrl(_baseUrlController.text);
    if (baseUrl.isEmpty) {
      setState(() => _status = 'Please enter a backend URL.');
      return;
    }
    final baseUri = Uri.tryParse(baseUrl);

    Uri endpoint;
    try {
      endpoint = Uri.parse('$baseUrl/api/compress');
    } catch (_) {
      setState(() => _status = 'Invalid backend URL.');
      return;
    }

    setState(() {
      _isCompressing = true;
      _status = 'Compressing using Python...';
      _compressedBytes = null;
      _downloadUrl = null;
    });

    _log('POST $endpoint | quality=$_quality | format=$_format');
    final client = HttpClient();
    try {
      final boundary = '----dart_form_boundary_${DateTime.now().microsecondsSinceEpoch}';
      final request = await client.postUrl(endpoint);
      request.headers.set('ngrok-skip-browser-warning', 'true');
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );

      void writeText(String value) => request.add(utf8.encode(value));

      void writeField(String name, String value) {
        writeText('--$boundary\r\n');
        writeText('Content-Disposition: form-data; name="$name"\r\n\r\n');
        writeText('$value\r\n');
      }

      writeField('quality', '$_quality');
      if (_format != 'auto') {
        writeField('format', _format);
      }

      final filename = _selectedName ?? file.name;
      final contentType = _guessMimeType();
      writeText('--$boundary\r\n');
      writeText(
        'Content-Disposition: form-data; name="image"; filename="${filename.replaceAll('"', '')}"\r\n',
      );
      writeText('Content-Type: $contentType\r\n\r\n');
      request.add(bytes);
      writeText('\r\n--$boundary--\r\n');

      final response = await request.close();
      final mimeType = response.headers.contentType?.mimeType;
      final body = await utf8.decodeStream(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        setState(() => _status = 'Backend error (${response.statusCode}): $body');
        _log('Backend error (${response.statusCode}): $body');
        return;
      }

      if (mimeType != null && mimeType != 'application/json') {
        setState(() {
          _status =
              'Unexpected response ($mimeType). If using ngrok, enable/skip the browser warning.';
        });
        _log('Unexpected content-type ($mimeType): $body');
        return;
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        setState(() => _status = 'Unexpected response from backend.');
        _log('Unexpected response: $body');
        return;
      }

      final downloadUrlRaw = decoded['downloadUrl']?.toString();
      if (downloadUrlRaw == null || downloadUrlRaw.isEmpty) {
        setState(() => _status = 'Backend response missing downloadUrl.');
        _log('Missing downloadUrl: $decoded');
        return;
      }

      Uri? downloadUri = Uri.tryParse(downloadUrlRaw);
      if (downloadUri == null) {
        setState(() => _status = 'Invalid downloadUrl from backend.');
        _log('Invalid downloadUrl: $downloadUrlRaw');
        return;
      }

      if (baseUri != null) {
        if (!downloadUri.isAbsolute) {
          downloadUri = baseUri.resolveUri(downloadUri);
        } else if (downloadUri.path.startsWith('/files/')) {
          // When running behind ngrok, FastAPI may construct `downloadUrl` with
          // the wrong scheme/host unless proxy headers are enabled.
          // If the backend gives us a `/files/...` path, force it onto the same
          // origin as the base URL the user entered.
          downloadUri = baseUri.replace(path: downloadUri.path, query: downloadUri.query);
        }
      }

      final outBytes = await _downloadBytes(client, downloadUri);
      setState(() {
        _compressedBytes = outBytes;
        _downloadUrl = downloadUri.toString();
        _status = 'Compressed.';
      });
      _log('Compression complete. Downloaded ${outBytes.length} bytes');
    } catch (error) {
      setState(() => _status = 'Error: $error');
      _log('Error during python compression: $error');
    } finally {
      client.close(force: true);
      setState(() => _isCompressing = false);
    }
  }

  Future<void> _saveCompressed() async {
    if (_compressedBytes == null) return;

    try {
      if (Platform.isAndroid) {
        final photos = await Permission.photos.request();
        final storage = await Permission.storage.request();
        if (!photos.isGranted && !storage.isGranted) {
          setState(() => _status = 'Permission denied.');
          _log('Storage/photos permission denied');
          return;
        }
      } else {
        final status = await Permission.photos.request();
        if (!status.isGranted) {
          setState(() => _status = 'Permission denied.');
          _log('Photo permission denied');
          return;
        }
      }

      final name = _selectedName ?? 'image.jpg';
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final result = await ImageGallerySaver.saveImage(
        _compressedBytes!,
        name: 'python_compressed_${stamp}_$name',
        quality: _quality,
      );

      final filePath = result['filePath']?.toString() ?? result['path']?.toString();
      setState(() => _status = filePath == null ? 'Saved.' : 'Saved: $filePath');
      _log('Saved to gallery: $filePath');
    } catch (error) {
      setState(() => _status = 'Save failed: $error');
      _log('Save failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _selectedBytes == null
        ? const SizedBox.shrink()
        : ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              _compressedBytes ?? _selectedBytes!,
              height: 220,
              fit: BoxFit.cover,
            ),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Python Compression'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _baseUrlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Backend URL',
                hintText: 'https://<your-subdomain>.ngrok-free.dev',
                border: OutlineInputBorder(),
                helperText:
                    'Android emulator: http://10.0.2.2:8000 • Real phone: http://<LAN-IP>:8000 or https://<ngrok>',
              ),
              onChanged: (_) {
                setState(() {});
              },
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: const Text('Use Emulator URL'),
                  onPressed: _isCompressing
                      ? null
                      : () {
                          setState(() {
                            _baseUrlController.text = 'http://10.0.2.2:8000';
                          });
                        },
                ),
                ActionChip(
                  label: const Text('Use Localhost'),
                  onPressed: _isCompressing
                      ? null
                      : () {
                          setState(() {
                            _baseUrlController.text = 'http://127.0.0.1:8000';
                          });
                        },
                ),
                ActionChip(
                  label: const Text('Use ngrok URL'),
                  onPressed: _isCompressing
                      ? null
                      : () {
                          setState(() {
                            _baseUrlController.text = _defaultNgrokBaseUrl;
                          });
                        },
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isCompressing ? null : _pickImage,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Upload Photo'),
            ),
            const SizedBox(height: 12),
            Center(child: preview),
            const SizedBox(height: 16),
            Text(
              'Compression Quality',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('80%'),
                  selected: _quality == 80,
                  onSelected: _isCompressing
                      ? null
                      : (selected) {
                          if (selected) setState(() => _quality = 80);
                        },
                ),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('90%'),
                  selected: _quality == 90,
                  onSelected: _isCompressing
                      ? null
                      : (selected) {
                          if (selected) setState(() => _quality = 90);
                        },
                ),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('100%'),
                  selected: _quality == 100,
                  onSelected: _isCompressing
                      ? null
                      : (selected) {
                          if (selected) setState(() => _quality = 100);
                        },
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _format,
              decoration: const InputDecoration(
                labelText: 'Output Format',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'auto', child: Text('Auto')),
                DropdownMenuItem(value: 'jpeg', child: Text('JPEG')),
                DropdownMenuItem(value: 'png', child: Text('PNG')),
                DropdownMenuItem(value: 'webp', child: Text('WebP')),
                DropdownMenuItem(value: 'avif', child: Text('AVIF')),
              ],
              onChanged: _isCompressing
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() => _format = value);
                    },
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: (_selectedBytes == null || _isCompressing) ? null : _compressWithPython,
              child: _isCompressing
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Compress (Python)'),
            ),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(
                _status!,
                style: TextStyle(
                  color: _status!.startsWith('Error') || _status!.startsWith('Backend error')
                      ? Colors.red
                      : Colors.green,
                ),
              ),
            ],
            if (_compressedBytes != null && _selectedBytes != null) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Original: ${_formatBytes(_selectedBytes!.length)}'),
                      Text('Compressed: ${_formatBytes(_compressedBytes!.length)}'),
                      Text('Quality: $_quality%'),
                      Text('Reduction: ${_compressionRatio()}'),
                      if (_downloadUrl != null) Text('URL: $_downloadUrl'),
                    ],
                  ),
                ),
              ),
            ],
            if (_compressedBytes != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _saveCompressed,
                icon: const Icon(Icons.save_alt),
                label: const Text('Save Compressed'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

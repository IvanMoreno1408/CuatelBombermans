// lib/widgets/signature_field.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

/// Campo de firma autocontenible.
/// No usamos `onSign` (algunas versiones no lo exponen). En su lugar,
/// ofrecemos un botón "Guardar firma" que exporta PNG y llama `onChanged`.
class SignatureField extends StatefulWidget {
  final String label;
  final bool required;
  final ValueChanged<Uint8List?> onChanged;

  const SignatureField({
    super.key,
    required this.label,
    this.required = false,
    required this.onChanged,
  });

  @override
  State<SignatureField> createState() => _SignatureFieldState();
}

class _SignatureFieldState extends State<SignatureField> {
  late final SignatureController _controller;
  Uint8List? _lastPng;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveSignature() async {
    if (_controller.isEmpty) {
      setState(() {
        _lastPng = null;
      });
      widget.onChanged(null);
      return;
    }
    final bytes = await _controller.toPngBytes();
    setState(() {
      _lastPng = bytes;
    });
    widget.onChanged(bytes);
  }

  void _clear() {
    _controller.clear();
    setState(() {
      _lastPng = null;
    });
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: DefaultTextStyle.of(context).style,
            children: [
              TextSpan(
                text: widget.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (widget.required)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(color: Colors.red),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          height: 180,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Signature(
              controller: _controller,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _clear,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Limpiar'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _saveSignature,
              icon: const Icon(Icons.save_alt),
              label: const Text('Guardar firma'),
            ),
            const SizedBox(width: 8),
            if (_lastPng != null)
              const Icon(Icons.check_circle, color: Colors.green),
          ],
        ),
      ],
    );
  }
}

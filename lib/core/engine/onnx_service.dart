import 'dart:developer' as developer;

import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';

/// Result of ONNX inference containing token embeddings.
class OnnxResult {
  /// Token embeddings [seq_len, 384] — L2-normalized.
  final List<List<double>> tokenEmbeddings;

  const OnnxResult(this.tokenEmbeddings);
}

/// Interface for ONNX model inference.
///
/// The service accepts pre-tokenized input_ids and attention_mask
/// (produced by the HuggingFace tokenizer) and returns token embeddings.
abstract class OnnxService {
  bool get isInitialized;

  /// Initializes the ONNX session.
  Future<void> initialize();

  /// Encodes pre-tokenized input and returns L2-normalized token embeddings.
  Future<OnnxResult?> runInference(List<int> inputIds, List<int> attentionMask);

  void dispose();
}

/// Real ONNX Runtime service using the `onnxruntime` Dart package.
class RealOnnxService implements OnnxService {
  OrtSession? _session;
  bool _initialized = false;

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
    try {
      // Load model bytes from bundled asset
      final assetBytes =
          await rootBundle.load('assets/minilm_target_token.onnx');
      final modelBytes = assetBytes.buffer.asUint8List();

      // Create session options and session from buffer
      final options = OrtSessionOptions();
      _session = OrtSession.fromBuffer(modelBytes, options);

      _initialized = true;
      developer.log(
        'ONNX Runtime initialized: inputs=${_session!.inputNames}, outputs=${_session!.outputNames}',
        name: 'OnnxService',
      );
    } catch (e) {
      developer.log(
        'Failed to initialize ONNX Runtime: $e',
        name: 'OnnxService',
        level: 1000,
      );
      _initialized = false;
    }
  }

  @override
  Future<OnnxResult?> runInference(
      List<int> inputIds, List<int> attentionMask) async {
    if (!_initialized || _session == null) return null;

    try {
      final seqLen = inputIds.length;

      // Create input tensors using the correct API
      final inputIdsTensor = OrtValueTensor.createTensorWithDataList(
        inputIds,
        [1, seqLen],
      );
      final attentionMaskTensor = OrtValueTensor.createTensorWithDataList(
        attentionMask,
        [1, seqLen],
      );

      // Map input names to tensors
      final inputs = <String, OrtValue>{
        _session!.inputNames[0]: inputIdsTensor,
        _session!.inputNames[1]: attentionMaskTensor,
      };

      // Run inference (synchronous)
      final runOptions = OrtRunOptions();
      final outputs = _session!.run(runOptions, inputs);

      // Get the first output (token embeddings)
      final outputTensor = outputs.first;
      if (outputTensor == null) return null;

      // Extract raw values as List<num>
      final rawValues = outputTensor.value;
      if (rawValues is! List<num>) return null;

      // Reshape: rawValues is [1, seq_len * 384] flattened
      // We need [seq_len, 384]
      const embedDim = 384;
      final tokenEmbeddings = <List<double>>[];

      for (int i = 0; i < seqLen; i++) {
        final start = i * embedDim;
        final end = start + embedDim;
        if (end <= rawValues.length) {
          final vec = List<double>.generate(
            embedDim,
            (j) => rawValues[start + j].toDouble(),
          );
          // L2-normalize
          double norm = 0;
          for (final v in vec) {
            norm += v * v;
          }
          if (norm > 0) {
            for (int j = 0; j < vec.length; j++) {
              vec[j] /= norm;
            }
          }
          tokenEmbeddings.add(vec);
        }
      }

      // Release tensors
      inputIdsTensor.release();
      attentionMaskTensor.release();
      for (final output in outputs) {
        output?.release();
      }
      runOptions.release();

      return OnnxResult(tokenEmbeddings);
    } catch (e) {
      developer.log('ONNX inference error: $e',
          name: 'OnnxService', level: 1000);
      return null;
    }
  }

  @override
  void dispose() {
    _session?.release();
    _session = null;
    _initialized = false;
  }
}

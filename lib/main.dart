// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import 'package:flutter_gpu_test/shaders.dart';

void main() {
  runApp(const MyApp());
}

extension DurationToDouble on Duration {
  /// Convert the duration.
  double toDouble() {
    return inMicroseconds / Duration.microsecondsPerSecond;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Flutter GPU Triangle Example',
      home: MyWidget(),
    );
  }
}

class MyWidget extends StatefulWidget {
  const MyWidget({super.key});

  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget>
    with SingleTickerProviderStateMixin {
  late Ticker ticker;
  late Stopwatch sw;
  late double iFrame;

  @override
  void initState() {
    super.initState();
    sw = Stopwatch();
    iFrame = 0;
    sw.start();
    ticker = Ticker(_onTick);
    ticker.start();
  }

  void _onTick(Duration time) {
    iFrame++;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: SurfacePainter(
        iFrame: iFrame,
        iTime: sw.elapsed.inMicroseconds / Duration.microsecondsPerSecond,
      ),
    );
  }
}

class SurfacePainter extends CustomPainter {
  SurfacePainter({
    required this.iTime,
    required this.iFrame,
  });

  final double iTime;
  final double iFrame;

  late gpu.HostBuffer transients;
  late gpu.RenderPass renderPass;
  late gpu.RenderPipeline pipeline;
  late gpu.CommandBuffer commandBuffer;
  gpu.Texture? texture;

  void createTexture(Size size) {
    texture = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate, size.width.toInt(), size.height.toInt(),
        enableRenderTargetUsage: true,
        enableShaderReadUsage: true,
        coordinateSystem: gpu.TextureCoordinateSystem.renderToTexture)!;

    final renderTarget = gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(texture: texture!, clearValue: Colors.lightBlue));

    commandBuffer = gpu.gpuContext.createCommandBuffer();
    renderPass = commandBuffer.createRenderPass(renderTarget);

    final vert = shaderLibrary['SimpleVertex']!;
    final frag = shaderLibrary['SimpleFragment']!;
    pipeline = gpu.gpuContext.createRenderPipeline(vert, frag);

    /// create a plane composed by 2 triangles that fit the entire display
    final vertices = Float32List.fromList([
      -1, -1, // 1st triangle bottom left
      1, -1, // 1st triangle bottom right
      -1, 1, // 1st triangle upper left
      1, 1, // 2nd triangle upper right
      -1, 1, // 2nd triangle upper left
      1, -1, // 2nd triangle bottom right
    ]);
    final verticesDeviceBuffer = gpu.gpuContext
        .createDeviceBufferWithCopy(ByteData.sublistView(vertices))!;

    renderPass.bindPipeline(pipeline);

    final verticesView = gpu.BufferView(
      verticesDeviceBuffer,
      offsetInBytes: 0,
      lengthInBytes: verticesDeviceBuffer.sizeInBytes,
    );
    renderPass.bindVertexBuffer(verticesView, 6);

    transients = gpu.gpuContext.createHostBuffer();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (texture == null) createTexture(size);

    /// Pack the fragment shader uniform into [bdata].
    var bdata = ByteData(16);
    bdata.setFloat32(0, size.width, Endian.little);
    bdata.setFloat32(4, size.height, Endian.little);
    bdata.setFloat32(8, iTime, Endian.little);
    bdata.setFloat32(12, iFrame, Endian.little);
    final uboBuffer = transients.emplace(bdata);

    /// Get the uniform then bind it with the [bdata] bytes.
    final uboUniform = pipeline.fragmentShader.getUniformSlot('UBO');

    renderPass.bindUniform(uboUniform, uboBuffer);

    renderPass.draw();

    commandBuffer.submit();

    final image = texture!.asImage();
    canvas.drawImage(image, Offset.zero, Paint());
  }

  @override
  bool shouldRepaint(SurfacePainter oldDelegate) =>
      oldDelegate.iFrame != iFrame;
}

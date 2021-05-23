import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:tflite/tflite.dart';
import 'package:image/image.dart' as imglib;
import 'package:http/http.dart' as http;
import 'package:audioplayers/audio_cache.dart';
import 'package:intl/intl.dart';
import 'package:flutter_beep/flutter_beep.dart';

import 'package:path_provider/path_provider.dart';

import 'package:amplify_flutter/amplify.dart';
import 'amplifyconfiguration.dart';
import 'package:amplify_storage_s3/amplify_storage_s3.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';


import 'dart:math';

import 'dart:async';
import './aws-ai/lib/src/RekognitionHandler.dart';

import './boundary_box.dart';

class FaceDetectionFromLiveCamera extends StatefulWidget {
  final locationValue;
  final deviceValue;

  FaceDetectionFromLiveCamera(this.locationValue,this.deviceValue);

  @override
  _FaceDetectionFromLiveCameraState createState() =>
      _FaceDetectionFromLiveCameraState(locationValue,deviceValue);
}

class _FaceDetectionFromLiveCameraState
    extends State<FaceDetectionFromLiveCamera> {
//for cameraController
  List<CameraDescription> cameras;
  CameraController cameraController;
  bool isDetecting = false;
  AudioCache player = new AudioCache();
  final alarm = "translate_tts.mp3";

//for setReco
  String _recognitions = "";
  Color borderColor = Colors.black;
  Color tempTextColor = Colors.black;
  Color conTextColor = Colors.black;
  int _condition = 0;
  int count = 0;

//for checkCondition
  bool tempFlag = false;
  bool maskFlag = false;
  double temp = 0;
  bool mask = false;

//URLs
  String dbEndPoint = "https://uc74mrfttj.execute-api.ap-northeast-2.amazonaws.com/prod/data";
  RekognitionHandler reko = new RekognitionHandler("AKIAY6KMVUFSUZ2M2A5N", "B1E9QXbVGgJlGPaj10mhDFs4esFRf8gBmlN3o3Pz", "ap-northeast-2");

//User Info
  String location;
  String deviceId;

  _FaceDetectionFromLiveCameraState(this.location, this.deviceId);

  @override
  void initState() {
    super.initState();
    _configureAmplify();
    loadModel();
    _initializeCamera();
  }

  void _configureAmplify() async {
    if (!mounted) return;

    // Add Pinpoint and Cognito Plugins
    Amplify.addPlugin(AmplifyStorageS3());
    Amplify.addPlugin(AmplifyAuthCognito());


    // Once Plugins are added, configure Amplify
    // Note: Amplify can only be configured once.
    try {
      await Amplify.configure(amplifyconfig);
      print('Successfully configured Amplify 🎉');
      print(location);
    } catch (e) {
      print('Could not configure Amplify ☠️');
      print(e);
    }
  }


  void loadModel() async {
    await Tflite.loadModel(
      model: "assets/ml_trained_model/yolov4_tiny.tflite",
      labels: "assets/ml_trained_model/yolov4_tiny.txt",
    );
  }


  void _initializeCamera() async {
    cameras = await availableCameras();
    cameraController = CameraController(cameras[0], ResolutionPreset.high);
    cameraController.initialize().then(
          (_) {
        if (!mounted) {
          return;
        }
        cameraController.startImageStream(
              (CameraImage img) {
            if (!isDetecting) {
              isDetecting = true;
              // object detection
              Tflite.detectObjectOnFrame(
                bytesList: img.planes.map(
                      (plane) {
                    return plane.bytes;
                  },
                ).toList(),
                imageHeight: img.height,
                imageWidth: img.width,
                numResultsPerClass: 2,
              ).then(
                    (recognitions) async{
                      //대상이 80% 이상의 확률로 사람으로 인식될 경우 이미지 추출 및 온도 체크 시
                  if (recognitions[0]["detectedClass"] == 'person' && recognitions[0]["confidenceInClass"]>=0.7) {
                    final captureImage = img;
                    setRecognitions(1);
                    await Future.delayed(const Duration(milliseconds: 800));
                    await DetectingPerson(captureImage);
                    await Future.delayed(const Duration(seconds: 5));
                  }
                  _condition = 0;
                  setRecognitions(_condition);

                  isDetecting = false;
                },
              );
            }
          },
        );
      },
    );
  }

  Future<void> DetectingPerson(CameraImage img) async {
    final imageByte = await convertYUV420toImageColor(img);
    writeImgFile(imageByte);
    checkMask(imageByte);
    checkTemp();
  }

// 온도 측정(시나리오)
  Future<void> checkTemp() async {
       temp = (Random().nextInt(15)+365)/10;
       tempFlag = true;
       if(maskFlag == true && tempFlag == true) {
         checkCondition();
       }
       else{print("온도 먼저");}
  }
// 마스크 체크(시나리오)
  Future<void> checkMask(img) async{
    final result = await reko.detectFaces(img);
    print(result);
    mask = true;
    count++;
    maskFlag = true;
    if(tempFlag==true && maskFlag == true){
      checkCondition();
    }
    else{print("마스크 먼저");}
  }

// 온도 및 마스크 판단
  void checkCondition() async {
    String pn = "N";

    maskFlag = tempFlag = false;

    if (temp >=37.5){
      _condition = 2;
      setRecognitions(_condition);
      await Future.delayed(const Duration(milliseconds: 800));
    }
    else{
      if (mask == true){
        pn = "P";
        _condition =4;
        setRecognitions(_condition);
        await Future.delayed(const Duration(milliseconds: 800));
      }
      else{
        _condition = 3;
        setRecognitions(_condition);
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }

    // if (temp< 38 && mask == true){
    //   pn = "P";
    //   setRecognitions(5);
    //   await Future.delayed(const Duration(milliseconds: 500));
    // }
    // else if (temp >=35){
    //   setRecognitions(2);
    //   await Future.delayed(const Duration(milliseconds: 500));
    // }
    // else if (temp <=38 && mask == false){
    //   setRecognitions(4);
    //   await Future.delayed(const Duration(milliseconds: 500));
    // }

    final date = DateTime.now();

    var resultDate = DateFormat("yyyyMMdd").format(date);
    var resultTime = DateFormat("HH:mm").format(date);
    print(resultTime);
    print(resultDate);

    http.Response response = await http.post(
      dbEndPoint,
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        "pk":location+deviceId+DateTime.now().toString(),
        "location": location,
        "device_id": deviceId,
        "mask": mask.toString(),
        "temperature": temp,
        "PN": pn,
        "check_day": resultDate,
        "check_time": resultTime
      },
      ),
    );
  }

// 이미지 바이트 추출
  Future<List> convertYUV420toImageColor(CameraImage image) async {
    try {
      final int width = image.width;
      final int height = image.height;
      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel;

      print("uvRowStride: " + uvRowStride.toString());
      print("uvPixelStride: " + uvPixelStride.toString());

      // imgLib -> Image package from https://pub.dartlang.org/packages/image
      var img = imglib.Image(width, height); // Create Image buffer

      // Fill image buffer with plane[0] from YUV420_888
      for (int x = 0; x < width; x++) {
        for (int y = 0; y < height; y++) {
          final int uvIndex =
              uvPixelStride * (x / 2).floor() + uvRowStride * (y / 2).floor();
          final int index = y * width + x;

          final yp = image.planes[0].bytes[index];
          final up = image.planes[1].bytes[uvIndex];
          final vp = image.planes[2].bytes[uvIndex];
          // Calculate pixel color
          int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
          int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91)
              .round()
              .clamp(0, 255);
          int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);
          // color: 0x FF  FF  FF  FF
          //           A   B   G   R
          img.data[index] = (0xFF << 24) | (b << 16) | (g << 8) | r;
        }
      }

      imglib.PngEncoder pngEncoder = new imglib.PngEncoder(level: 0, filter: 0);
      List<int> png = pngEncoder.encodeImage(img);
      String base64SourceImage = base64Encode(png);

      return png;
      //muteYUVProcessing = false;
    } catch (e) {
      print(">>>>>>>>>>>> ERROR:" + e.toString());
    }
    return null;
  }

// 이미지 S3 전송
  Future<void> writeImgFile(List<int> data) async {
    Directory tempDir = await getApplicationDocumentsDirectory();

    String tempPath = tempDir.path;

    var filePath = tempPath + '/captured_person.png';
    print(filePath);
    final imageFile = File(filePath);
    await imageFile.writeAsBytes(data);

    final key = new DateTime.now().toString();
    UploadFileResult result = await Amplify.Storage.uploadFile(
      key: key,
      local: imageFile,
    );
  }

// 화면 출력 상태 설정
  void setRecognitions(int condition) {
    setState(() {
      switch(condition) {
        case 1:
          _recognitions = "잠시만 기다려주세요";
          borderColor = Colors.black;
          tempTextColor = Colors.black;
          conTextColor = Colors.white;
          break;
        case 2:
          _recognitions = "체온 이상 입장불가";
          borderColor = Colors.red;
          tempTextColor = Colors.red;
          conTextColor = Colors.red;
          FlutterBeep.beep(false);
          break;
        case 3:
          _recognitions = "마스크 미착용 입장불가";
          borderColor = Colors.red;
          tempTextColor = Colors.green;
          conTextColor = Colors.red;
          FlutterBeep.beep(false);
          break;
        case 4:
          _recognitions = "입장허용";
          borderColor = Colors.green;
          tempTextColor = Colors.green;
          conTextColor = Colors.green;
          FlutterBeep.beep();
          break;
        case 5:
          _recognitions = "초기화 중 입니다";
          borderColor = Colors.white;
          tempTextColor = Colors.black;
          conTextColor = Colors.white;
          break;
        default:
          _recognitions = "";
          borderColor = Colors.black;
          tempTextColor = Colors.black;
          conTextColor = Colors.black;
          break;

      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Size screen = MediaQuery.of(context).size;
    return Container(
      constraints: const BoxConstraints.expand(),
      decoration: BoxDecoration(
        border: Border.all(
          width: 5,
          color: borderColor,
        )
      ),
      child: cameraController == null
          ? Container(
        alignment: Alignment.center,
        child: CircularProgressIndicator(),
      )
          : Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: cameraController.value.aspectRatio,
              child: CameraPreview(cameraController),
            ),
          ),
          Positioned(
          left: (screen.width / 4),
          bottom: -(screen.height - 80),
          width: screen.width,
          height: screen.height,
          child: Text(
          "$_recognitions",
          style: TextStyle(
          backgroundColor: Colors.black,
          color: conTextColor,
          fontSize: 20.0,
          fontWeight: FontWeight.bold,
          ),
          ),
          ),
          Positioned(
            left: 40,
            top: 40,
            width: screen.width,
            height: screen.height,
            child: Text(
              "$temp",
              style: TextStyle(
                backgroundColor: Colors.black,
                color: tempTextColor,
                fontSize: 30.0,
                fontWeight: FontWeight.bold,
              ),
            ),
          )
          // BoundaryBox(
          //     _recognitions == null ? [] : _recognitions,
          //     math.max(_imageHeight, _imageWidth),
          //     math.min(_imageHeight, _imageWidth),
          //     screen.height,
          //     screen.width),
        ],
      ),
    );
  }
}

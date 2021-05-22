import 'package:flutter/material.dart';
import 'mask_detection_camera.dart';



void main(){

  runApp(
      MaterialApp(
          home: Scaffold(
              body: _Login()
          )
      )
  );

}


class _Login extends StatelessWidget
{

  final myController_location = TextEditingController();
  final myController_device = TextEditingController();

  @override
  Widget build(BuildContext context) {

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Container(
            margin: EdgeInsets.all(8),
            child:TextField(
              controller: myController_location,
            )
        ),
        Container(
            margin: EdgeInsets.all(8),
            child:TextField(
              controller: myController_device,
            )
        ),
        FloatingActionButton(
          child:Icon(Icons.camera),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder:(context) => MyApp(myController_location.text,myController_device.text)),
            );
          },
        )
      ],
    );

  }
}


class MyApp extends StatelessWidget {
  final locationValue;
  final deviceValue;
  MyApp(this.locationValue, this.deviceValue);
  @override

  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Human Face Mask Detector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        primaryColor: Colors.indigo,
      ),
      home: FaceDetectionFromLiveCamera(locationValue, deviceValue),
    );
  }
}
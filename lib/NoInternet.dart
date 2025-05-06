import 'package:flutter/material.dart';

class NoInternetConnection extends StatefulWidget {
  const NoInternetConnection({Key? key}) : super(key: key);

  @override
  State<NoInternetConnection> createState() => _NoInternetConnectionState();
}

class _NoInternetConnectionState extends State<NoInternetConnection> {
  double height = 0;
  double weight = 0;
  @override
  Widget build(BuildContext context) {
    Orientation currentOrientation = MediaQuery.of(context).orientation;
    if (currentOrientation == Orientation.portrait) {
      height = MediaQuery.of(context).size.height;
    } else {
      height = MediaQuery.of(context).size.width;
    }
    weight = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Stack(
            children: [

              Container(
                height: height,
                width: weight,
                child: Column(
                  children: [


                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 300, 20, 100),
                      child: Container(
                        child:  Text(
                          'CONNECTION IS LOST',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20.0,
                            fontWeight: FontWeight.normal,

                            fontStyle: FontStyle.normal,



                          ),
                        ),
                      ),
                    ),


                  ],
                ),
              ),
            ],
          ) ],
      ),
    );
  }
}
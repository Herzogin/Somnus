import 'package:flutter/material.dart';

class ActivityScreen extends StatefulWidget {
  @override
  _ActivityScreenState createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        //title: Text(
        //"Analyse deiner Aktivitäten",
        //style: TextStyle(fontSize: 26, fontWeight: FontWeight.normal),
        //),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1E1164), Color(0xFF2752E4)]),
        ),
        child: Center(
          child: Image.asset('assets/images/analyse.png'),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:frontend_somnus/providers/states.dart';
import 'package:frontend_somnus/screens/disclaimer_screen.dart';
import 'package:frontend_somnus/screens/hypnogram_screen.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'screens/tabs_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:foreground_service/foreground_service.dart';
import 'widgets/singletons/ble_device_controller.dart';
import './screens/edit_data_screen.dart';

int disclaimerScreen;
int tutorialScreen;
List<double> accelData;
List<double> latestAccelData;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences prefs = await SharedPreferences.getInstance();
  disclaimerScreen = prefs.getInt("disclaimerScreen");
  await prefs.setInt("disclaimerScreen", 1);
  //tutorialScreen = prefs.getInt("tutorialScreen");
  //await prefs.setInt("tutorialScreen", 1);
  Intl.defaultLocale = "de_DE";

  await maybeStartFGS();
  runApp(MyApp());
}

//use an async method so we can await
void maybeStartFGS() async {
  accelData = new List();
  latestAccelData = new List();

  ///if the app was killed+relaunched, this function will be executed again
  ///but if the foreground service stayed alive,
  ///this does not need to be re-done
  if (!(await ForegroundService.foregroundServiceIsStarted())) {
    await ForegroundService.setServiceIntervalSeconds(1);

    //necessity of editMode is dubious (see function comments)
    await ForegroundService.notification.startEditMode();

    await ForegroundService.notification.setTitle("Somnus");
    await ForegroundService.notification.setText(DEVICE_NOT_CONNECTED);

    await ForegroundService.notification.finishEditMode();

    await ForegroundService.startForegroundService(foregroundServiceFunction);
    await ForegroundService.getWakeLock();
  }

  ///this exists solely in the main app/isolate,
  ///so needs to be redone after every app kill+relaunch
  await ForegroundService.setupIsolateCommunication((data) {
    accelData = new List.from(accelData)..addAll(data);
    latestAccelData = data;
  });
}

void foregroundServiceFunction() async {
  if (!ForegroundService.isIsolateCommunicationSetup) {
    accelData = new List();
    latestAccelData = new List();

    ForegroundService.setupIsolateCommunication((data) {
      accelData = new List.from(accelData)..addAll(data);
      latestAccelData = data;
    });
  }

  // TODO: check how to communicate in background!

  print("Received accelerometer records: " + (accelData.length / 3).toString());

  if (latestAccelData.length > 0) {
    foregroundServiceSetText(DEVICE_CONNECTED);
    print("Latest accelerometer record: x=" +
        latestAccelData[0].toString() +
        " y=" +
        latestAccelData[1].toString() +
        " z=" +
        latestAccelData[2].toString());

    accelData = new List();
    latestAccelData = new List();
  } else {
    foregroundServiceSetText(DEVICE_NOT_CONNECTED);
  }

  //ForegroundService.sendToPort("message from bg isolate");
}

void foregroundServiceSetText(String text) async {
  if ((await ForegroundService.notification.getText()) != text) {
    ForegroundService.notification.setText(text);
  }
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();

    _activateForegroundService();
  }

  void _activateForegroundService() async {
    if (!(await ForegroundService.foregroundServiceIsStarted())) {
      maybeStartFGS();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => DataStates(),
      child: MaterialApp(
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [
          const Locale('de', ''), // German, no country code
        ],
        title: 'Somnus',
        initialRoute: disclaimerScreen == 0 || disclaimerScreen == null
            ? "disclaimerScreen"
            : "/",
        routes: {
          '/': (context) => TabsScreen(),
          'disclaimerScreen': (context) => DisclaimerScreen(),
          EditDataScreen.routeName: (ctx) => EditDataScreen(),
          HypnogramScreen.routeName: (ctx) => HypnogramScreen(Colors.white)
        },
        theme: ThemeData(
            //primaryColor: Color(0xFF0F24D9),
            //accentColor: Color(0xFF680FD9),
            primaryColor: Color(0xFF00008B),
            accentColor: Color(0xFF570899)
            //  cardColor: Color(0xFF680FD9),
            ),
      ),
    );
  }
}

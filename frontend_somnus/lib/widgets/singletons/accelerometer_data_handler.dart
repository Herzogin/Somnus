import 'dart:async';
import 'dart:io';

import 'package:frontend_somnus/screens/database_helper.dart';
import 'package:frontend_somnus/widgets/singletons/file_writer.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

enum Status {
  accelDataWrittenToDB,
  accelDataNotWrittenToDB,
}

const String SHARED_PREFS_LAST_ID = 'lastWrittenID';

var accelDataHandler = AccelDataHandler();

class AccelDataHandler {
  static AccelDataHandler _accelDataHandler = new AccelDataHandler
      ._internal();

  factory AccelDataHandler() {
    return _accelDataHandler;
  }

  AccelDataHandler._internal();

  SharedPreferences sharedPrefs;
  final dbHelper = DatabaseHelper.instance;
  Timer _firstAccelDataToBackendTimer;
  Timer _accelDataToBackendTimer;
  Timer _firstAccelDataToCSVTimer;
  Timer _accelDataToCSVTimer;

  String _constructStringForCSVOneLine(String date, String time, String accX, String accY, String accZ) {
    final String line = date + " " + time + "," + accX + "," + accY + "," + accZ + "\r\n";
    return line;
  }

  Future<void> writeAccelDataToDB(double x, double y, double z) async {
    Map<String, dynamic> row = new Map();

    final DateFormat serverFormaterDate = DateFormat('yyyy-MM-dd');
    final DateFormat serverFormaterTime = DateFormat('HH:mm:ss');
    final date = DateTime.now();
    final currentDate = serverFormaterDate.format(date);
    // Adding 500 ms manually, because the backend needs exactly the same
    // value for the ms. Reading the ms from DateTime.now has little variations
    // that cause strange behaviour.
    final currentTime = serverFormaterTime.format(date) + ":500";

    row[DatabaseHelper.columnDate] = currentDate;
    row[DatabaseHelper.columnTime] = currentTime;
    row[DatabaseHelper.columnX] = x;
    row[DatabaseHelper.columnY] = y;
    row[DatabaseHelper.columnZ] = z;
    row[DatabaseHelper.columnLUX] = 0;
    row[DatabaseHelper.columnT] = 0;

    //print(row);
    await dbHelper.insert(row);
  }

  bool isDataToBackendTimerActive() {
    return _accelDataToBackendTimer != null;
  }

  void cancelDataToBackendTimer() {
    _accelDataToBackendTimer.cancel();
  }

  void startDataToBackendTimer() {
    final DateFormat dateFormaterHours = new DateFormat("HH");
    final DateTime currentDate = new DateTime.now();
    DateTime twelfAm = new DateTime(
        currentDate.year, currentDate.month, currentDate.day, 12, 5, 0);
    DateTime twelfPm = new DateTime(
        currentDate.year, currentDate.month, currentDate.day, 24, 5, 0);
    Duration durationTillFirstExecution;
    int currentHour = int.parse(dateFormaterHours.format(currentDate));

    // calculate duration until 12 am or pm, to write data the first time
    if (currentHour < 12) {
      durationTillFirstExecution = twelfAm.difference(currentDate);
    } else {
      durationTillFirstExecution = twelfPm.difference(currentDate);
    }

    _firstAccelDataToBackendTimer = Timer.periodic((durationTillFirstExecution), (Timer t) {
      // after the timer was executed the first time, cancel it and set a new timer that
      // executes every 12 hours
      _accelDataToBackendTimer = Timer.periodic((Duration(hours: 12)), (Timer t) => _dataToBackend());
      _dataToBackend();
      _firstAccelDataToBackendTimer.cancel();
    });
  }

  bool isDataToCSVTimerActive() {
    return _accelDataToCSVTimer != null;
  }

  void cancelDataToCSVTimer() {
    _accelDataToCSVTimer.cancel();
  }

  Future<void> startDataToCSVTimer() async {
    sharedPrefs = await SharedPreferences.getInstance();

    final DateFormat dateFormaterHours = new DateFormat("HH");
    final DateTime currentDate = new DateTime.now();
    int currentHour = int.parse(dateFormaterHours.format(currentDate));
    DateTime nextFullHour = new DateTime(
        currentDate.year, currentDate.month, currentDate.day, currentHour + 1, 0, 0);
    Duration durationTillFirstExecution = nextFullHour.difference(currentDate);

    print("Duration: " + durationTillFirstExecution.toString());

    _firstAccelDataToCSVTimer = Timer.periodic((durationTillFirstExecution), (Timer t) {
      // after the timer was executed the first time, cancel it and set a new timer that
      // executes every hour
      _accelDataToCSVTimer = Timer.periodic((Duration(hours: 1)), (Timer t) => _dataToCSV());
      _dataToCSV();
      _firstAccelDataToCSVTimer.cancel();
    });
  }

  Future<void> _dataToBackend() async {
    var res = await _uploadFile();
    await dbHelper.resultsToDb(res);
    await fileWriter.deleteFile();
  }

  Future<void> _dataToCSV() async {
    final lastWrittenID = sharedPrefs.getInt(SHARED_PREFS_LAST_ID);
    List<Map<String, dynamic>> allRowsDescendingOrder = await dbHelper.queryLastNRows(3600); // query rows of last hour
    List<Map<String, dynamic>> allRows = new List();

    // rows are sorted in descending order, so first thing is to mirror the list
    for (int i=allRowsDescendingOrder.length - 1; i>=0; i--) {
      allRows.add(allRowsDescendingOrder[i]);
    }

    // if no rows where written
    if (lastWrittenID != null) {
      // check if there are already written rows in new allRows list
      // if so, remove them and return the residual rows
      allRows = _removeAlreadyWrittenEntries(allRows, lastWrittenID);
    }

    // if there are rows to write, write them to CSV, else, do nothing
    if (allRows != null) {
      await _writeAlltoCSV(allRows);
      // save last written row ID to shared prefs for next time
      sharedPrefs.setInt(SHARED_PREFS_LAST_ID, allRows.last[DatabaseHelper.columnId]);
    }
  }

  Future<void> _writeAlltoCSV(List<Map<String, dynamic>> allRows) async {
    String fileContentStr = "";

    // construct a big string for CSV file
    allRows.forEach((row) {
      //print(row);
      fileContentStr += _constructStringForCSVOneLine(
          row[DatabaseHelper.columnDate],
          row[DatabaseHelper.columnTime],
          row[DatabaseHelper.columnX].toString(),
          row[DatabaseHelper.columnY].toString(),
          row[DatabaseHelper.columnZ].toString());
    });

    // write one line to file
    await fileWriter.writeLine(fileContentStr);
  }

  List<Map<String, dynamic>> _removeAlreadyWrittenEntries(List<Map<String, dynamic>> allRows, int lastWrittenID) {
    int indexOfId = -1;

    // search all entries, whether the lastWrittenId is in the list
    for (int i=0; i<allRows.length; i++) {
      if (allRows[i][DatabaseHelper.columnId] == lastWrittenID) {
        // if id was found, save the index
        indexOfId = i;
        break;
      }
    }

    if (indexOfId >= 0) {
      indexOfId += 1;
      allRows.removeRange(0, indexOfId);
    }

    return allRows;
  }

  Future<String> _uploadFile() async {
    http.Response response;
    var request = http.MultipartRequest('POST', Uri.parse('http://192.168.1.78:5000/data'));
    final filePath = await fileWriter.getFilePath();

    try {
      var multipartFile = http.MultipartFile.fromBytes(
        'file',
        File(filePath).readAsBytesSync(),
        filename: filePath.split("/").last, //filename argument is mandatory!
      );
      request.files.add(multipartFile);
      response = await http.Response.fromStream(await request.send());
      print("Result: ${response.statusCode}");
      print(response.body);
      print(response.body.length);

      return response.body;
    } catch (error) {
      print('Error uploading file');
    }
    return null;
  }
}

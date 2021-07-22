import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:autoconnection/models/model_logdata.dart';
import '../models/model_bleDevice.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'package:location/location.dart' as loc;
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../utils/util.dart';
import 'package:wakelock/wakelock.dart';

class Scanscreen extends StatefulWidget {
  @override
  ScanscreenState createState() => ScanscreenState();
}

class ScanscreenState extends State<Scanscreen> {
  BleManager _bleManager = BleManager();
  bool _isScanning = false;
  bool _connected = false;
  String currentMode = 'normal';
  String message = '';
  Peripheral _curPeripheral; // 연결된 장치 변수
  List<BleDeviceItem> deviceList = []; // BLE 장치 리스트 변수
  List<DeviceInfo> savedDeviceList = []; // 저장된 BLE 장치 리스트 변수
  List<String> savedList = []; // 추가된 장치 리스트 변수
  //List<BleDeviceItem> myDeviceList = [];
  String _statusText = ''; // BLE 상태 변수
  loc.LocationData currentLocation;
  int dataSize = 0;
  loc.Location location = new loc.Location();
  StreamSubscription<loc.LocationData> _locationSubscription;
  StreamSubscription monitoringStreamSubscription;
  String _error;
  String geolocation;
  String currentDeviceName = '';
  Timer _timer;
  int _start = 0;
  bool isStart = false;
  Map<String, String> idMapper;
  // double width;
  TextEditingController _textFieldController;
  String currentState = '';

  String firstImagePath = '';
  String secondImagePath = '';
  Future<List<DeviceInfo>> _allDeviceTemp;

  // Future<List<DateTime>> allDatetime;

  String currentTemp;
  String currentHumi;
  String resultText = '';

  String strMapper(String input) {
    if (input == 'scan') {
      return '대기 중';
    } else if (input == 'connecting') {
      return '연결 중';
    } else if (input == 'end') {
      return '전송 완료';
    } else if (input == 'connect') {
      return '데이터 전송 중';
    } else
      return '';
  }

  @override
  void initState() {
    // _allDeviceTemp = DBHelper().getAllDevices();

    super.initState();
    // getCurrentLocation();
    Wakelock.enable();
    currentDeviceName = '';
    currentTemp = '-';
    currentHumi = '-';
    init();
  }

  @override
  void dispose() {
    // ->> 사라진 위젯에서 cancel하려고 해서 에러 발생
    super.dispose();
    // _stopMonitoringTemperature();
    _bleManager.destroyClient();
  }

  endRoutine(value, index) {
    if (value != null) {
      print("??? " + deviceList[index].getserialNumber());
      savedList.remove(deviceList[index].getserialNumber());
      deviceList.remove(deviceList[index]);
      print('저장목록 : ' + savedList.toString());
      print('디바이스목록 : ' + deviceList.toString());
    }
    setState(() {});
  }

  // TODO: 관선님 이부분 서버 전송부분인데 여기 수정하시면 될 것 같습니다.
  Future<Post> sendtoServer(Data data) async {
    Socket socket = await Socket.connect('175.126.232.236', 9981);
    String body = '';
    body += data.deviceName +
        '|0|' +
        data.time +
        '|' +
        data.time +
        '|N|0|E|0|' +
        data.temper +
        '|' +
        data.humi +
        '|0|0|0|0;';
    print('connected server & Send to server');
    socket.write(body);
    socket.close();
    // try {
    //   var uriResponse =
    //       await client.post('http://175.126.232.236:9981/', body: {
    //     "OPSI3997771|0|2019-09-05 05:33:58|2019-09-05 05:33:59|N|37.236982|E|126.581735|27.435112|66.114288|254|-1023|-139|30;"
    //   });

    //   // print(await client.get(uriResponse.body.['uri']));
    // } catch (e) {
    //   print(e);
    //   return null;
    // } finally {
    //   print('send !');
    //   client.close();
    // }
  }

  Future<void> monitorCharacteristic(BleDeviceItem device, flag) async {
    await _runWithErrorHandling(() async {
      Service service = await device.peripheral.services().then((services) =>
          services.firstWhere((service) =>
              service.uuid == '00001000-0000-1000-8000-00805f9b34fb'));

      List<Characteristic> characteristics = await service.characteristics();
      Characteristic characteristic = characteristics.firstWhere(
          (characteristic) =>
              characteristic.uuid == '00001002-0000-1000-8000-00805f9b34fb');

      _startMonitoringTemperature(
          characteristic.monitor(transactionId: device.peripheral.identifier),
          device.peripheral,
          flag);
    });
  }

  Uint8List getMinMaxTimestamp(Uint8List notifyResult) {
    return notifyResult.sublist(12, 18);
  }

  void _stopMonitoringTemperature() async {
    monitoringStreamSubscription?.cancel();
  }

  void _startMonitoringTemperature(Stream<Uint8List> characteristicUpdates,
      Peripheral peripheral, flag) async {
    monitoringStreamSubscription?.cancel();

    monitoringStreamSubscription = characteristicUpdates.listen(
      (notifyResult) async {
        // print('혹시 이거임 ?' + notifyResult.toString());
        //데이터 삭제 읽기
        // if (notifyResult[10] == 0x0a) {
        //   \
        //   await showMyDialog_StartTransport(context);
        //   Navigator.of(context).pop();
        // }
        //
        if (notifyResult[10] == 0x03) {
          int index = -1;
          for (var i = 0; i < deviceList.length; i++) {
            if (deviceList[i].peripheral.identifier == peripheral.identifier) {
              index = i;
              break;
            }
          }
          // 최소 최대 인덱스
          if (index != -1) {
            Uint8List minmaxStamp = getMinMaxTimestamp(notifyResult);
            deviceList[index].logDatas.clear();
            var writeCharacteristics = await peripheral.writeCharacteristic(
                '00001000-0000-1000-8000-00805f9b34fb',
                '00001001-0000-1000-8000-00805f9b34fb',
                Uint8List.fromList([0x55, 0xAA, 0x01, 0x05] +
                    deviceList[index].getMacAddress() +
                    [0x04, 0x06] +
                    minmaxStamp),
                true);
          }
        }
        if (notifyResult[10] == 0x05) {
          int index = -1;
          for (var i = 0; i < deviceList.length; i++) {
            if (deviceList[i].peripheral.identifier == peripheral.identifier) {
              index = i;
              break;
            }
          }
          if (index != -1) {
            LogData temp = transformData(notifyResult);
            // print(temp.temperature.toString());
            if (deviceList[index].lastUpdateTime != null) {
              if (temp.timestamp
                  .toLocal()
                  .isAfter(deviceList[index].lastUpdateTime)) {
                deviceList[index].logDatas.add(temp);
              }
            } else {
              deviceList[index].logDatas.add(temp);
            }
          }
        }
        if (notifyResult[10] == 0x06) {
          int index = -1;
          for (var i = 0; i < deviceList.length; i++) {
            if (deviceList[i].peripheral.identifier == peripheral.identifier) {
              index = i;
              break;
            }
          }

          Data sendData = new Data(
            battery: '',
            deviceName: 'Sensor_' + deviceList[index].getserialNumber(),
            humi: '',
            temper: deviceList[index].getTemperature().toString(),
            lat: '',
            lng: '',
            time: new DateTime.now().toLocal().toString(),
            lex: '',
          );
          // 전송 시작
          print('전송 시작');
          Post temp = await sendtoServer(sendData);

          // 전송 결과
          // print(temp.body);

          // TODO: sendtoserver() 성공적으로 전송이 될 때만 업데이트.

          // 최근 업로드 기록 업데이트
          await DBHelper().updateLastUpdate(
              peripheral.identifier, DateTime.now().toLocal());
          setState(() {
            deviceList[index].lastUpdateTime = DateTime.now().toLocal();
          });
          print(deviceList[index].getserialNumber() +
              ' 총(개) : ' +
              deviceList[index].logDatas.length.toString());

          setState(() {
            deviceList[index].connectionState = 'end';
            resultText = '[' +
                deviceList[index].getserialNumber() +
                '] ' +
                deviceList[index].logDatas.length.toString() +
                ' 개(분) 전송 완료';
          });
        }
      },
      onError: (error) {
        final BleError temperrors = error;
        if (temperrors.errorCode.value == 201) {
          print('그르게');
          int index = -1;
          for (var i = 0; i < deviceList.length; i++) {
            if (deviceList[i].peripheral.identifier == peripheral.identifier) {
              index = i;
              break;
            }
          }
          if (index != -1) {
            setState(() {
              deviceList[index].connectionState = 'scan';
            });
            print(deviceList[index].connectionState);
          }
        }

        print("Error while monitoring characteristic \n$error");
      },
      cancelOnError: true,
    );
  }

  void startRoutine(int index, flag) async {
    // 여기 !
    await monitorCharacteristic(deviceList[index], flag);
    String unixTimestamp =
        (DateTime.now().toUtc().millisecondsSinceEpoch / 1000)
            .toInt()
            .toRadixString(16);
    Uint8List timestamp = Uint8List.fromList([
      int.parse(unixTimestamp.substring(0, 2), radix: 16),
      int.parse(unixTimestamp.substring(2, 4), radix: 16),
      int.parse(unixTimestamp.substring(4, 6), radix: 16),
      int.parse(unixTimestamp.substring(6, 8), radix: 16),
    ]);

    Uint8List macaddress = deviceList[index].getMacAddress();
    print('쓰기 시작 ');
    if (flag == 0) {
      var writeCharacteristics = await deviceList[index]
          .peripheral
          .writeCharacteristic(
              '00001000-0000-1000-8000-00805f9b34fb',
              '00001001-0000-1000-8000-00805f9b34fb',
              Uint8List.fromList([0x55, 0xAA, 0x01, 0x05] +
                  deviceList[index].getMacAddress() +
                  [0x02, 0x04] +
                  timestamp),
              true);
    } else if (flag == 1) {
      // 데이터 삭제 시작
      var writeCharacteristics = await deviceList[index]
          .peripheral
          .writeCharacteristic(
              '00001000-0000-1000-8000-00805f9b34fb',
              '00001001-0000-1000-8000-00805f9b34fb',
              Uint8List.fromList([0x55, 0xAA, 0x01, 0x05] +
                  deviceList[index].getMacAddress() +
                  [0x09, 0x01, 0x01]),
              true);
    }
  }

  // 타이머 시작
  // 00:00:00
  void startTimer() {
    if (isStart == true) return;
    const oneSec = const Duration(seconds: 15);
    _timer = new Timer.periodic(
      oneSec,
      (Timer timer) => setState(
        () {
          if (isStart == false) isStart = true;
          _start = _start + 1;
          // if (_start % 5 == 0) {
          print(_start);
          _checkPermissions();
        },
      ),
    );
  }

  Future<Post> sendData(Data data) async {
    var client = http.Client();
    try {
      var uriResponse =
          await client.post('http://175.126.232.236/_API/saveData.php', body: {
        "isRegularData": "true",
        "tra_datetime": data.time,
        "tra_temp": data.temper,
        "tra_humidity": data.humi,
        "tra_lat": data.lat,
        "tra_lon": data.lng,
        "de_number": data.deviceName,
        "tra_battery": data.battery,
        "tra_impact": data.lex
      });
      // print(await client.get(uriResponse.body.['uri']));
    } finally {
      client.close();
    }
  }

  // BLE 초기화 함수
  void init() async {
    //ble 매니저 생성
    // savedDeviceList = await DBHelper().getAllDevices();
    setState(() {});
    await _bleManager
        .createClient(
            restoreStateIdentifier: "hello",
            restoreStateAction: (peripherals) {
              peripherals?.forEach((peripheral) {
                print("Restored peripheral: ${peripheral.name}");
              });
            })
        .catchError((e) => print("Couldn't create BLE client  $e"))
        .then((_) => _checkPermissions()) //매니저 생성되면 권한 확인
        .catchError((e) => print("Permission check error $e"));
  }

  // 권한 확인 함수 권한 없으면 권한 요청 화면 표시, 안드로이드만 상관 있음
  _checkPermissions() async {
    if (Platform.isAndroid) {
      if (await Permission.location.request().isGranted) {
        print('입장하냐?');
        scan();
        return;
      }
      Map<Permission, PermissionStatus> statuses =
          await [Permission.location].request();
      if (statuses[Permission.location].toString() ==
          "PermissionStatus.granted") {
        //getCurrentLocation();
        scan();
      }
    } else {
      scan();
    }
  }

  // 1. 엑셀 2. 서버구조 3. 영어 과제
  //scan 함수
  void scan() async {
    if (!_isScanning) {
      print('스캔시작');
      deviceList.clear(); //기존 장치 리스트 초기화
      //SCAN 시작
      if (Platform.isAndroid) {
        _bleManager.startPeripheralScan(scanMode: ScanMode.lowLatency).listen(
            (scanResult) {
          //listen 이벤트 형식으로 장치가 발견되면 해당 루틴을 계속 탐.
          //periphernal.name이 없으면 advertisementData.localName확인 이것도 없다면 unknown으로 표시
          //print(scanResult.peripheral.name);
          var name = scanResult.peripheral.name ??
              scanResult.advertisementData.localName ??
              "Unknown";
          // 기존에 존재하는 장치면 업데이트
          // print('lenght: ' + deviceList.length.toString());
          var findDevice = deviceList.any((element) {
            if (element.peripheral.identifier ==
                scanResult.peripheral.identifier) {
              element.peripheral = scanResult.peripheral;
              element.advertisementData = scanResult.advertisementData;
              element.rssi = scanResult.rssi;

              if (element.connectionState == 'scan') {
                int index = -1;
                for (var i = 0; i < deviceList.length; i++) {
                  if (deviceList[i].peripheral.identifier ==
                      scanResult.peripheral.identifier) {
                    index = i;
                    break;
                  }
                }
                if (index != -1) {
                  connect(index, 0);
                }
              }
              // BleDeviceItem currentItem = new BleDeviceItem(
              //     name,
              //     scanResult.rssi,
              //     scanResult.peripheral,
              //     scanResult.advertisementData,
              //     'scan');

              // Data sendData = new Data(
              //   battery: currentItem.getBattery().toString(),
              //   deviceName:
              //       'OP_' + currentItem.getDeviceId().toString().substring(7),
              //   humi: currentItem.getHumidity().toString(),
              //   temper: currentItem.getTemperature().toString(),
              //   lat: currentLocation.latitude.toString() ?? '',
              //   lng: currentLocation.longitude.toString() ?? '',
              //   time: new DateTime.now().toString(),
              //   lex: '',
              // );
              // sendtoServer(sendData);

              return true;
            }
            return false;
          });
          // 새로 발견된 장치면 추가
          if (!findDevice) {
            if (name != "Unknown") {
              // print(name);
              // if (name.substring(0, 3) == 'IOT') {
              if (name != null) {
                if (name.length > 3) {
                  if (name.substring(0, 4) == 'T301') {
                    BleDeviceItem currentItem = new BleDeviceItem(
                        name,
                        scanResult.rssi,
                        scanResult.peripheral,
                        scanResult.advertisementData,
                        'scan');
                    print(currentItem.peripheral.identifier);
                    print('인 !');

                    deviceList.add(currentItem);

                    connect(deviceList.length - 1, 0);
                  }
                }
              }
            }
          }
          //55 aa - 01 05 - a4 c1 38 ec 59 06 - 01 - 07 - 08 b6 17 70 61 00 01
          //55 aa - 01 05 - a4 c1 38 ec 59 06 - 02 - 04 - 60 43 24 96
          //페이지 갱신용
          setState(() {});
        }, onError: (error) {
          print('스캔 중지당함');
          _bleManager.stopPeripheralScan();
        });
      }
      setState(() {
        //BLE 상태가 변경되면 화면도 갱신
        _isScanning = true;
        setBLEState('<스캔중>');
      });
    } else {
      // await _bleManager.destroyClient();
      //
      // //스캔중이었으면 스캔 중지
      // // TODO: 일단 주석!
      // _bleManager.stopPeripheralScan();
      // setState(() {
      //   //BLE 상태가 변경되면 페이지도 갱신
      //   _isScanning = false;
      //   setBLEState('Stop Scan');
      // });
    }
  }

  //BLE 연결시 예외 처리를 위한 래핑 함수
  _runWithErrorHandling(runFunction) async {
    try {
      await runFunction();
    } on BleError catch (e) {
      print("BleError caught: ${e.errorCode.value} ${e.reason}");
    } catch (e) {
      if (e is Error) {
        debugPrintStack(stackTrace: e.stackTrace);
      }
      print("${e.runtimeType}: $e");
    }
  }

  // 상태 변경하면서 페이지도 갱신하는 함수
  void setBLEState(txt) {
    setState(() => _statusText = txt);
  }

  //연결 함수
  connect(index, flag) async {
    bool goodConnection = false;
    if (_connected) {
      //이미 연결상태면 연결 해제후 종료
      print('mmmmmmm 여기냐 설마 ?? mmmmmmmmm');
      // await _curPeripheral?.disconnectOrCancelConnection();
      setState(() {
        deviceList[index].connectionState = 'scan';
      });
      return false;
    }

    //선택한 장치의 peripheral 값을 가져온다.
    Peripheral peripheral = deviceList[index].peripheral;

    DeviceInfo temp = await DBHelper().getDevice(peripheral.identifier);
    if (temp.macAddress == '123') {
      print('create');
      await DBHelper().createData(DeviceInfo(
          macAddress: peripheral.identifier,
          // Init Time - 10일 전
          lastUpdate: DateTime.now().toLocal().subtract(Duration(days: 30))));
    } else {
      setState(() {
        deviceList[index].lastUpdateTime = temp.lastUpdate.toLocal();
      });

      print('이미존재함 : ' + deviceList[index].getserialNumber());
      print('Last Update Time1 : ' + temp.lastUpdate.toString());
      // TODO: 시간 수정(3개) 필수 !
      print('Enable Time1 : ' +
          DateTime.now().toLocal().subtract(Duration(minutes: 5)).toString());
      if (temp.lastUpdate
          .isBefore(DateTime.now().toLocal().subtract(Duration(minutes: 5)))) {
        // deviceList[index].connectionState = 'connecting';
      } else {
        print('아직 시간이 안됨 !');
        // print('Last Update Time : ' + temp.lastUpdate.toString());
        // print('Enable Time : ' +
        //     DateTime.now().toLocal().subtract(Duration(minutes: 5)).toString());
        setState(() {
          deviceList[index].connectionState = 'scan';
        });
        return;
      }
    }
    print(deviceList[index].getserialNumber() + ' : Connection Start\n');
    //해당 장치와의 연결상태를 관촬하는 리스너 실행
    peripheral
        .observeConnectionState(emitCurrentValue: false)
        .listen((connectionState) {
      // 연결상태가 변경되면 해당 루틴을 탐.
      print(currentState);
      switch (connectionState) {
        case PeripheralConnectionState.connected:
          {
            currentState = 'connected';
            //연결됨
            print('연결 완료 !');
            _curPeripheral = peripheral;
            // getCurrentLocation();
            //peripheral.
            deviceList[index].connectionState = 'connect';
            setBLEState('연결 완료');

            // startRoutine(index);
            Stream<CharacteristicWithValue> characteristicUpdates;

            print('결과 ' + characteristicUpdates.toString());

            // //데이터 받는 리스너 핸들 변수
            // StreamSubscription monitoringStreamSubscription;

            // //이미 리스너가 있다면 취소
            // //  await monitoringStreamSubscription?.cancel();
            // // ?. = 해당객체가 null이면 무시하고 넘어감.

            // monitoringStreamSubscription = characteristicUpdates.listen(
            //   (value) {
            //     print("read data : ${value.value}"); //데이터 출력
            //   },
            //   onError: (error) {
            //     print("Error while monitoring characteristic \n$error"); //실패시
            //   },
            //   cancelOnError: true, //에러 발생시 자동으로 listen 취소
            // );
            // peripheral.writeCharacteristic(BLE_SERVICE_UUID, characteristicUuid, value, withResponse)
          }
          break;
        case PeripheralConnectionState.connecting:
          {
            deviceList[index].connectionState = 'connecting';

            // showMyDialog_Connecting(context);

            print('연결중입니당!');
            currentState = 'connecting';
            setBLEState('<연결 중>');
          } //연결중
          break;
        case PeripheralConnectionState.disconnected:
          {
            // if (currentState == 'connecting')
            //  showMyDialog_Disconnect(context);
            //해제됨
            _connected = false;
            print("${peripheral.name} has DISCONNECTED");
            //TODO: 일단 주석 !
            // _stopMonitoringTemperature();
            deviceList[index].connectionState = 'scan';
            setBLEState('<연결 종료>');

            print('여긴 오냐');
            return false;
            //if (failFlag) {}
          }
          break;
        case PeripheralConnectionState.disconnecting:
          {
            setBLEState('<연결 종료중>');
          } //해제중
          break;
        default:
          {
            //알수없음...
            print("unkown connection state is: \n $connectionState");
          }
          break;
      }
    });

    _runWithErrorHandling(() async {
      //해당 장치와 이미 연결되어 있는지 확인
      bool isConnected = await peripheral.isConnected();
      if (isConnected) {
        print('device is already connected');
        //이미 연결되어 있기때문에 무시하고 종료..
        return this._connected;
      }

      //연결 시작!
      await peripheral
          .connect(
        isAutoConnect: false,
      )
          .then((_) {
        this._curPeripheral = peripheral;
        //연결이 되면 장치의 모든 서비스와 캐릭터리스틱을 검색한다.
        peripheral
            .discoverAllServicesAndCharacteristics()
            .then((_) => peripheral.services())
            .then((services) async {
          print("PRINTING SERVICES for ${peripheral.name}");
          //각각의 서비스의 하위 캐릭터리스틱 정보를 디버깅창에 표시한다.
          for (var service in services) {
            print("Found service ${service.uuid}");
            List<Characteristic> characteristics =
                await service.characteristics();
            for (var characteristic in characteristics) {
              print("charUUId: " + "${characteristic.uuid}");
            }
          }
          //모든 과정이 마무리되면 연결되었다고 표시

          startRoutine(index, flag);
          // if (flag == 1) {
          //   showMyDialog_finishStart(
          //       context, deviceList[index].getserialNumber());
          // }
          _connected = true;
          _isScanning = true;
          setState(() {});
        });
      });
      print(_connected.toString());
      return _connected;
    });
  }

  //장치 화면에 출력하는 위젯 함수
  list() {
    if (deviceList?.isEmpty == true) {
      return Container(
          decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [customeBoxShadow()],
              borderRadius: BorderRadius.all(Radius.circular(5))),
          height: MediaQuery.of(context).size.height * 0.7,
          width: MediaQuery.of(context).size.width * 0.99,
          child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  children: [
                    Text(
                      '디바이스를 스캔중입니다.',
                      style: lastUpdateTextStyle(context),
                    ),
                  ],
                ),
                Column(
                  children: [
                    Text('블루투스가 켜져있나 확인해주세요.\n',
                        style: lastUpdateTextStyle(context)),
                  ],
                )
              ]));
    } else {
      return ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: deviceList.length,
        itemBuilder: (BuildContext context, int index) {
          return Container(
            decoration: BoxDecoration(
                color: deviceList[index].lastUpdateTime == null ||
                        deviceList[index].lastUpdateTime.isBefore(DateTime.now()
                            .toLocal()
                            .subtract(Duration(minutes: 5)))
                    ? Color.fromRGBO(0x61, 0xB2, 0xD0, 1)
                    : Colors.white,
                boxShadow: [customeBoxShadow()],
                borderRadius: BorderRadius.all(Radius.circular(5))),
            height: MediaQuery.of(context).size.height * 0.10,
            width: MediaQuery.of(context).size.width * 0.99,
            child: Column(children: [
              Expanded(
                  flex: 4,
                  child: InkWell(
                    onTap: () async {},
                    child: Container(
                        padding: EdgeInsets.only(top: 5, left: 2),
                        width: MediaQuery.of(context).size.width * 0.98,
                        decoration: BoxDecoration(
                            color: Color.fromRGBO(255, 255, 255, 0),
                            //boxShadow: [customeBoxShadow()],
                            borderRadius: BorderRadius.all(Radius.circular(5))),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                Text(deviceList[index].getserialNumber(),
                                    style: boldTextStyle),
                                // Image(
                                //   image: AssetImage('images/T301.png'),
                                //   fit: BoxFit.contain,
                                //   width:
                                //       MediaQuery.of(context).size.width * 0.10,
                                //   height:
                                //       MediaQuery.of(context).size.width * 0.10,
                                // ),

                                Text(
                                    strMapper(
                                        deviceList[index].connectionState),
                                    style: strMapper(deviceList[index]
                                                .connectionState) ==
                                            '대기 중'
                                        ? boldTextStyle
                                        : redBoldTextStyle),
                              ],
                            ),
                            deviceList[index].lastUpdateTime == null
                                ? Text('최근 업로드 시간 : --일 --:--:--',
                                    style: lastUpdateTextStyle(context))
                                : Text(
                                    '최근 업로드 시간 : ' +
                                        DateFormat('dd일 HH:mm:ss').format(
                                            deviceList[index].lastUpdateTime),
                                    style: lastUpdateTextStyle(context),
                                  ),
                          ],
                        )),
                  )),
            ]),
          );
        },
        //12,13 온도
        separatorBuilder: (BuildContext context, int index) {
          return Divider();
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    return MaterialApp(
        builder: (context, child) {
          return MediaQuery(
            child: child,
            data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
          );
        },
        debugShowCheckedModeBanner: false,
        title: 'OPTILO',
        theme: ThemeData(
          // primarySwatch: Colors.grey,
          primaryColor: Color.fromRGBO(0x61, 0xB2, 0xD0, 1),
          //canvasColor: Colors.transparent,
        ),
        home: Scaffold(
          appBar: AppBar(
              // backgroundColor: Color.fromARGB(22, 27, 32, 1),
              title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 8,
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text(
                    'Thermo Cert',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: MediaQuery.of(context).size.width / 18,
                        fontWeight: FontWeight.w600),
                  ),
                ]),
              ),
              Expanded(
                  flex: 4,
                  child:
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    new IconButton(
                      icon: new Icon(Icons.add, size: 30),
                      onPressed: () {
                        // addDeviceDialog(context);
                      },
                    )
                  ])),
            ],
          )),
          body: Container(
            width: MediaQuery.of(context).size.width,
            decoration: BoxDecoration(
              color: Color.fromRGBO(240, 240, 240, 1),
              boxShadow: [customeBoxShadow()],
              //color: Color.fromRGBO(81, 97, 130, 1),
            ),
            child: Column(
              children: <Widget>[
                Expanded(
                    flex: 9,
                    child: Container(
                        margin: EdgeInsets.only(
                            top: MediaQuery.of(context).size.width * 0.035),
                        width: MediaQuery.of(context).size.width * 0.97,
                        // height:
                        //     MediaQuery.of(context).size.width * 0.45,

                        child: list()) //리스트 출력
                    ),
                Expanded(
                    flex: 1,
                    child: Container(
                        color: Color.fromRGBO(200, 200, 200, 1),
                        margin: EdgeInsets.only(
                          top: MediaQuery.of(context).size.width * 0.015,
                          bottom: MediaQuery.of(context).size.width * 0.015,
                        ),
                        // bottom: MediaQuery.of(context).size.width * 0.035),
                        width: MediaQuery.of(context).size.width * 0.97,
                        // height:
                        //     MediaQuery.of(context).size.width * 0.45,

                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              resultText,
                              style: boldTextStyle,
                            ),
                          ],
                        )) //리스트 출력
                    ),
              ],
            ),
          ),
        ));
  }

  TextStyle lastUpdateTextStyle(BuildContext context) {
    return TextStyle(
      fontSize: MediaQuery.of(context).size.width / 26,
      color: Color.fromRGBO(5, 5, 5, 1),
      fontWeight: FontWeight.w700,
    );
  }

  TextStyle updateTextStyle(BuildContext context) {
    return TextStyle(
      fontSize: MediaQuery.of(context).size.width / 24,
      color: Color.fromRGBO(0xe8, 0x52, 0x55, 1),
      fontWeight: FontWeight.w500,
    );
  }

  TextStyle redBoldTextStyle = TextStyle(
    fontSize: 22,
    color: Color.fromRGBO(0xE0, 0x71, 0x51, 1),
    fontWeight: FontWeight.w900,
  );
  TextStyle boldTextStyle = TextStyle(
    fontSize: 22,
    color: Color.fromRGBO(21, 21, 21, 1),
    fontWeight: FontWeight.w800,
  );
  TextStyle bigTextStyle(BuildContext context) {
    return TextStyle(
      fontSize: MediaQuery.of(context).size.width / 10,
      color: Color.fromRGBO(50, 50, 50, 1),
      fontWeight: FontWeight.w400,
    );
  }

  TextStyle thinTextStyle = TextStyle(
    fontSize: 22,
    color: Color.fromRGBO(244, 244, 244, 1),
    fontWeight: FontWeight.w500,
  );

  BoxShadow customeBoxShadow() {
    return BoxShadow(
        color: Colors.black.withOpacity(0.2),
        offset: Offset(0, 1),
        blurRadius: 6);
  }

  TextStyle whiteTextStyle(BuildContext context) {
    return TextStyle(
      fontSize: MediaQuery.of(context).size.width / 18,
      color: Color.fromRGBO(255, 255, 255, 1),
      fontWeight: FontWeight.w500,
    );
  }

  TextStyle btnTextStyle = TextStyle(
    fontSize: 20,
    color: Color.fromRGBO(255, 255, 255, 1),
    fontWeight: FontWeight.w700,
  );

  Uint8List stringToBytes(String source) {
    var list = new List<int>();
    source.runes.forEach((rune) {
      if (rune >= 0x10000) {
        rune -= 0x10000;
        int firstWord = (rune >> 10) + 0xD800;
        list.add(firstWord >> 8);
        list.add(firstWord & 0xFF);
        int secondWord = (rune & 0x3FF) + 0xDC00;
        list.add(secondWord >> 8);
        list.add(secondWord & 0xFF);
      } else {
        list.add(rune >> 8);
        list.add(rune & 0xFF);
      }
    });
    return Uint8List.fromList(list);
  }

  String bytesToString(Uint8List bytes) {
    StringBuffer buffer = new StringBuffer();
    for (int i = 0; i < bytes.length;) {
      int firstWord = (bytes[i] << 8) + bytes[i + 1];
      if (0xD800 <= firstWord && firstWord <= 0xDBFF) {
        int secondWord = (bytes[i + 2] << 8) + bytes[i + 3];
        buffer.writeCharCode(
            ((firstWord - 0xD800) << 10) + (secondWord - 0xDC00) + 0x10000);
        i += 4;
      } else {
        buffer.writeCharCode(firstWord);
        i += 2;
      }
    }
    return buffer.toString();
  }

  _checkPermissionCamera() async {
    if (await Permission.camera.request().isGranted) {
      scan();
      return '';
    }
    Map<Permission, PermissionStatus> statuses =
        await [Permission.camera, Permission.storage].request();
    //print("여기는요?" + statuses[Permission.location].toString());
    if (statuses[Permission.camera].toString() == "PermissionStatus.granted" &&
        statuses[Permission.storage].toString() == 'PermissionStatus.granted') {
      scan();
      return 'Pass';
    }
  }

  getCurrentLocation() async {
    bool _serviceEnabled;
    loc.PermissionStatus _permissionGranted;
    loc.LocationData _locationData;

    _serviceEnabled = await location.serviceEnabled();
    if (!_serviceEnabled) {
      _serviceEnabled = await location.requestService();
      if (!_serviceEnabled) {
        return;
      }
    }

    _permissionGranted = await location.hasPermission();
    if (_permissionGranted == loc.PermissionStatus.denied) {
      _permissionGranted = await location.requestPermission();
      if (_permissionGranted != loc.PermissionStatus.granted) {
        return;
      }
    }

    _locationData = await location.getLocation();
    print('lat: ' + _locationData.latitude.toString());
    setState(() {
      currentLocation = _locationData;
    });
  }
}

showMyDialog_finishStart(BuildContext context, String deviceName) {
  bool manuallyClosed = false;
  Future.delayed(Duration(seconds: 2)).then((_) {
    if (!manuallyClosed) {
      Navigator.of(context).pop();
    }
  });
  return showDialog(
    barrierDismissible: false,
    context: context,
    builder: (context) {
      return Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.0)),
        backgroundColor: Color.fromRGBO(0x61, 0xB2, 0xD0, 1),
        // elevation: 16.0,
        child: Container(
            width: MediaQuery.of(context).size.width / 3,
            height: MediaQuery.of(context).size.height / 3.5,
            padding: EdgeInsets.all(10.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  flex: 4,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Icon(
                        Icons.check_box,
                        color: Colors.white,
                        size: MediaQuery.of(context).size.width / 5,
                      ),
                      Text(deviceName,
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 20)),
                      Text("운송이 시작되었습니다. ",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 18),
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ],
            )),
      );
    },
  );
}

showMyDialog_Connecting(BuildContext context) {
  bool manuallyClosed = false;
  Future.delayed(Duration(seconds: 2)).then((_) {
    if (!manuallyClosed) {
      Navigator.of(context).pop();
    }
  });
  return showDialog(
    barrierDismissible: false,
    context: context,
    builder: (context) {
      return Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.0)),
        backgroundColor: Color.fromRGBO(0x61, 0xB2, 0xD0, 1),
        elevation: 16.0,
        child: Container(
            width: MediaQuery.of(context).size.width / 3,
            height: MediaQuery.of(context).size.height / 4,
            padding: EdgeInsets.all(10.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  flex: 4,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Icon(
                        Icons.bluetooth,
                        color: Colors.white,
                        size: MediaQuery.of(context).size.width / 5,
                      ),
                      Text("데이터 전송을 시작합니다 !",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 18),
                          textAlign: TextAlign.center),
                      Text("로딩이 되지 않으면 다시 눌러주세요.",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14),
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ],
            )),
      );
    },
  );
}

showMyDialog_StartTransport(BuildContext context) {
  bool manuallyClosed = false;
  Future.delayed(Duration(seconds: 2)).then((_) {
    if (!manuallyClosed) {
      Navigator.of(context).pop();
    }
  });
  return showDialog(
    barrierDismissible: false,
    context: context,
    builder: (context) {
      return Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.0)),
        backgroundColor: Color.fromRGBO(0x61, 0xB2, 0xD0, 1),
        elevation: 16.0,
        child: Container(
            width: MediaQuery.of(context).size.width / 3,
            height: MediaQuery.of(context).size.height / 4,
            padding: EdgeInsets.all(10.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  flex: 4,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Icon(
                        Icons.check_box,
                        color: Colors.white,
                        size: MediaQuery.of(context).size.width / 5,
                      ),
                      Text("운송을 시작합니다. ",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 20),
                          textAlign: TextAlign.center),
                      // Text("안전한 운행되세요.",
                      //     style: TextStyle(
                      //         color: Colors.white,
                      //         fontWeight: FontWeight.w600,
                      //         fontSize: 14),
                      //     textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ],
            )),
      );
    },
  );
}

//Datalog Parsing
LogData transformData(Uint8List notifyResult) {
  return new LogData(
      temperature: getLogTemperature(notifyResult),
      humidity: getLogHumidity(notifyResult),
      timestamp: getLogTime(notifyResult));
}

getLogTime(Uint8List fetchData) {
  int tmp =
      ByteData.sublistView(fetchData.sublist(12, 16)).getInt32(0, Endian.big);
  DateTime time = DateTime.fromMillisecondsSinceEpoch(tmp * 1000, isUtc: true);

  return time;
}

getLogHumidity(Uint8List fetchData) {
  int tmp =
      ByteData.sublistView(fetchData.sublist(18, 20)).getInt16(0, Endian.big);

  return tmp / 100;
}

getLogTemperature(Uint8List fetchData) {
  int tmp =
      ByteData.sublistView(fetchData.sublist(16, 18)).getInt16(0, Endian.big);

  return tmp / 100;
}

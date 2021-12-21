class VersionChecker {
  String appName = '';
  String version = '';
  String downloadLink = '';
  VersionChecker({this.appName, this.downloadLink, this.version});
  VersionChecker.fromJson(Map<String, dynamic> json) {
    appName = json['app_name'];
    version = json['version'];
    downloadLink = json['download_link'];
    // status = int.parse(json['tra_transport_state']);
    // print(deviceName);
    // print(destName);
    // print(status.toString());
  }
}

class UserDevice {
  String deviceName = '';
  String destName = '';
  String deviceNumber = '';
  int status = -1;

  UserDevice({this.destName, this.deviceName, this.deviceNumber});

  UserDevice.fromJson(Map<String, dynamic> json) {
    // deviceName = json['de_name'];
    // destName = json['node_name'];
    deviceNumber = json['de_number'];
    // status = int.parse(json['tra_transport_state']);
    // print(deviceName);
    // print(destName);
    print(deviceNumber);
    // print(status.toString());
  }
}

class UserDeviceList {
  final List<UserDevice> userDevices;
  UserDeviceList({this.userDevices});

  factory UserDeviceList.fromJson(List<dynamic> parsedJson) {
    List<UserDevice> userDevices = new List<UserDevice>();
    userDevices = parsedJson.map((i) => UserDevice.fromJson(i)).toList();
    return new UserDeviceList(userDevices: userDevices);
  }
}

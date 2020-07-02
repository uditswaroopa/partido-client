import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:partido_client/linear_icons_icons.dart';
import 'package:partido_client/model/bill.dart';
import 'package:retrofit/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api.dart';
import 'api/api_service.dart';
import 'model/group.dart';
import 'model/report.dart';
import 'model/user.dart';

class AppState extends ChangeNotifier {
  Api api = ApiService.getApi();

  User _currentUser = new User();
  Group _selectedGroup = new Group(users: []);
  List<Group> _myGroups = [];
  List<Bill> _bills = [];
  Report _report = new Report(balances: []);
  int _selectedGroupId = -1; // initial value to check if id must be loaded or not
  Map _availableBillCategories = new Map();
  DateTime now = DateTime.now();
  Map<int, String> _processedBillListTitles;

  void initAppState() async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    HttpResponse<User> _loginStatusResponse = await api.getLoginStatus();
    if (_loginStatusResponse.response.statusCode == 200) {
      _currentUser = _loginStatusResponse.data;
      _myGroups = await api.getMyGroups();
      notifyListeners();
      // Get current user and his groups first. Then check if user logged
      // in has a preferred group to see and if he can get it's details.
      // (the user may have logged in with an other account, where he cannot
      // see the same groups as before)
      if (_selectedGroupId == -1) {
        int preferredGroupId = preferences.getInt('SELECTEDGROUP');
        for (Group group in _myGroups) {
          if (group.id == preferredGroupId) {
            _selectedGroupId = preferredGroupId;
            reloadReport();
            _selectedGroup = group;
            reloadBillList();
            break;
          }
        }
      }
    }
    _availableBillCategories = loadAvailableBillCategories();
  }

  void clearAppState() async {
    _selectedGroupId = -1;
    _selectedGroup = new Group(users: []);
    _bills = [];
    _report = new Report(balances: []);
  }

  void refreshAppState() async {
    _selectedGroup = await api.getGroup(_selectedGroupId);
    _bills = await api.getBillsForGroup(_selectedGroupId);
    _processedBillListTitles = processBillListTitles(_bills);
    _report = await api.getReportForGroup(_selectedGroupId);
    _myGroups = await api.getMyGroups();
    notifyListeners();
  }

  void addBill(Bill bill) {
    _bills.add(bill);
    notifyListeners();
  }

  void replaceBillList(List<Bill> billList) {
    _bills = billList;
    notifyListeners();
  }

  List<Bill> getBills() {
    return _bills;
  }

  Map<int, String> getProcessedBillListTitles() {
    return _processedBillListTitles;
  }

  Report getReport() {
    return _report;
  }

  void changeSelectedGroup(int groupId) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setInt("SELECTEDGROUP", groupId);
    _selectedGroupId = groupId;
    reloadSelectedGroup();
    reloadBillList();
    reloadReport();
  }

  void reloadSelectedGroup() async {
    _selectedGroup = await api.getGroup(_selectedGroupId);
    notifyListeners();
  }

  void reloadBillList() async {
    _bills = await api.getBillsForGroup(_selectedGroupId);
    _processedBillListTitles = processBillListTitles(_bills);
    notifyListeners();
  }

  void reloadReport() async {
    _report = await api.getReportForGroup(_selectedGroupId);
    notifyListeners();
  }

  void reloadMyGroups() async {
    _myGroups = await api.getMyGroups();
    notifyListeners();
  }

  int getSelectedGroupId() {
    return _selectedGroupId;
  }

  Group getSelectedGroup() {
    return _selectedGroup;
  }

  User getCurrentUser() {
    return _currentUser;
  }

  void setCurrentUser(User user) {
    _currentUser = user;
    notifyListeners();
  }

  List<Group> getMyGroups() {
    return _myGroups;
  }

  User getUserFromGroupById(int creatorId) {
    for (User user in _selectedGroup.users) {
      if (user.id == creatorId) {
        return user;
      }
    }
  }

  /// 0 = false
  /// 1 = true
  void setRememberLoginStatus(String boolAsNumber) async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    preferences.setString("REMEMBERLOGIN", boolAsNumber);
  }

  Future<String> getRememberLoginStatus() async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    return preferences.getString("REMEMBERLOGIN");
  }

  Map loadAvailableBillCategories() {
    Map billCategories = new Map();
    billCategories["SUBSCRIPTIONS_DONATIONS"] = LinearIcons.calendar_check;
    billCategories["BARS_RESTAURANTS"] = LinearIcons.glass2;
    billCategories["EDUCATION"] = LinearIcons.graduation_hat;
    billCategories["FOOD_GROCERIES"] = LinearIcons.bread;
    billCategories["FAMILY_FRIENDS"] = LinearIcons.group_work;
    billCategories["LEISURE_ENTERTAINMENT"] = LinearIcons.ticket;
    billCategories["HEALTH_DRUGSTORES"] = LinearIcons.heart_pulse;
    billCategories["HOUSEHOLD_UTILITIES"] = LinearIcons.couch;
    billCategories["MEDIA_ELECTRONICS"] = LinearIcons.laptop;
    billCategories["TRAVEL_VACATION"] = LinearIcons.earth;
    billCategories["SHOPPING"] = LinearIcons.bag;
    billCategories["MISCELLANEOUS"] = LinearIcons.leaf;
    billCategories["TAXES_DUTIES"] = LinearIcons.calculator2;
    billCategories["TRANSPORT_CAR"] = LinearIcons.bus2;
    billCategories["UNCATEGORIZED"] = LinearIcons.cart;
    billCategories["INSURANCE_FINANCE"] = LinearIcons.apartment;
    return billCategories;
  }

  Map getAvailableBillCategories() {
    return _availableBillCategories;
  }

  Map<int, String> processBillListTitles(List<Bill> list) {
    Map<int, String> processBillListTitles = new Map();
    Map<String, String> titleUsed = new Map();
    for (int i=0; i < list.length; i++) {
      if (isToday(list[i]) && titleUsed['TODAY'] == null) {
        processBillListTitles[i] = 'TODAY';
        titleUsed['TODAY'] = "true";
      } else if (isYesterday(list[i]) && titleUsed['YESTERDAY'] == null) {
        processBillListTitles[i] = 'YESTERDAY';
        titleUsed['YESTERDAY'] = "true";
      } else if (isThisWeek(list[i]) && titleUsed['THIS_WEEK'] == null) {
        processBillListTitles[i] = 'THIS_WEEK';
        titleUsed['THIS_WEEK'] = "true";
      } else if (isThisMonth(list[i]) && titleUsed['THIS_MONTH'] == null) {
        processBillListTitles[i] = 'THIS_MONTH';
        titleUsed['THIS_MONTH'] = "true";
      } else {
        //TODO: handle all months...
      }
    }
    print(processBillListTitles);//TODO: remove print
    return processBillListTitles;
  }

  bool isToday(Bill bill) {
    if (DateTime.parse(bill.creationDate).isAfter(startOfToday())
        && DateTime.parse(bill.creationDate).isBefore(endOfToday())) {
      return true;
    }
    return false;
  }

  bool isYesterday(Bill bill) {
    if (DateTime.parse(bill.creationDate).isAfter(startOfYesterday()) &&
        DateTime.parse(bill.creationDate).isBefore(startOfToday())) {
      return true;
    }
    return false;
  }

  bool isThisWeek(Bill bill) {
    if (DateTime.parse(bill.creationDate).isAfter(startOfThisWeek()) &&
        DateTime.parse(bill.creationDate).isBefore(startOfYesterday())) {
      return true;
    }
    return false;
  }

  bool isThisMonth(Bill bill) {
    if (DateTime.parse(bill.creationDate).isAfter(startOfThisMonth()) &&
        DateTime.parse(bill.creationDate).isBefore(startOfThisWeek())) {
      return true;
    }
    return false;
  }

  DateTime startOfToday() {
    return DateTime(now.year, now.month, now.day);
  }

  DateTime startOfYesterday() {
    return startOfToday().subtract(Duration(days: 1));
  }

  DateTime startOfThisWeek() {
    return startOfToday().subtract(Duration(days: now.weekday));
  }

  DateTime startOfThisMonth() {
    return startOfToday().subtract(Duration(days: now.day));
  }

  DateTime endOfToday() {
    return DateTime(now.year, now.month, now.day, 23, 59, 59, 999, 999);
  }
}

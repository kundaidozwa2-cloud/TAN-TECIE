// TAN TECIE - Murehwa - Two Shops In One
class TanTecie {
  static const String company = "TAN TECIE";
  static const String town = "Murehwa";
  static const String phone = "0772 123 456"; // CHANGE TO YOUR NUMBER
  static const String ecocash = "0772 123 456"; // CHANGE TO YOUR ECOCASH
  static const String address = "Murehwa Centre, Murehwa"; // CHANGE TO YOUR PLACE

  static String receipt({
    required String shop, // "CAKE" or "BEAUTY"
    required String receiptNo,
    required List<Map<String, dynamic>> items,
    required double total,
    required String payment, // Cash / EcoCash / Card
    required String customer,
    required String note,
  }) {
    String shopTitle = shop == "CAKE" ? "CAKE SHOP" : "BEAUTY & WELLNESS";
    String prefix = shop == "CAKE" ? "TT-CAKE-" : "TT-BEAUTY-";
    StringBuffer b = StringBuffer();
    b.writeln("--------------------------------");
    b.writeln("        $company");
    b.writeln("        $shopTitle");
    b.writeln("        $town");
    b.writeln("--------------------------------");
    b.writeln("Date: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}");
    b.writeln("Receipt No: $prefix$receiptNo");
    b.writeln("Customer: $customer");
    b.writeln("--------------------------------");
    for (var it in items) {
      b.writeln("${it['qty']}x ${it['name']}  \$${it['price']}");
    }
    b.writeln("--------------------------------");
    b.writeln("TOTAL:                   \$$total");
    b.writeln("Payment: $payment");
    b.writeln("EcoCash: $ecocash");
    b.writeln("--------------------------------");
    b.writeln("Thank you! Tatenda!");
    b.writeln(note);
    b.writeln("Call us: $phone");
    b.writeln("$company - $town");
    b.writeln("--------------------------------");
    return b.toString();
  }

  // CAKE SHOP MENU
  static List<Map<String, dynamic>> cakes = [
    {"name": "Birthday Cake (Small)", "price": 15.0},
    {"name": "Birthday Cake (Medium)", "price": 25.0},
    {"name": "Birthday Cake (Large)", "price": 35.0},
    {"name": "Wedding Cake", "price": 80.0},
    {"name": "Cupcakes x6", "price": 10.0},
    {"name": "Muffins", "price": 5.0},
    {"name": "Bread Loaf", "price": 3.0},
  ];

  // BEAUTY & WELLNESS MENU
  static List<Map<String, dynamic>> beauty = [
    {"name": "Hair - Braiding", "price": 15.0},
    {"name": "Hair - Weave / Wig", "price": 20.0},
    {"name": "Nails - Manicure", "price": 10.0},
    {"name": "Nails - Pedicure", "price": 12.0},
    {"name": "Facial", "price": 15.0},
    {"name": "Massage", "price": 20.0},
    {"name": "Makeup", "price": 25.0},
  ];
}

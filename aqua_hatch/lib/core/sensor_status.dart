String sensorStatusLabel(String? status, {required String source}) =>
    switch (status) {
      'ok' => 'อ่านค่าจาก $source',
      'not_found' => 'ไม่พบเซนเซอร์ ตรวจสายและไฟเลี้ยง',
      'multiple_sensors' => 'พบหลายหัววัด ต้องเลือกรหัสหัววัดก่อน',
      'converting' => 'กำลังวัดค่า…',
      'crc_error' => 'ข้อมูลเสียหาย ตรวจสายและสัญญาณรบกวน',
      'timeout' => 'หัววัดไม่ตอบ ตรวจไฟ สาย A/B และที่อยู่',
      'invalid_value' => 'ค่าที่อ่านอยู่นอกช่วง ตรวจรุ่นและหน่วย',
      'stale' => 'ยังไม่ได้รับค่าใหม่จากหัววัด',
      'unsupported_power' => 'ต้องต่อไฟเลี้ยงหัววัดแบบ 3 สาย',
      'not_configured' => 'รอตั้งค่าตามคู่มือหัววัด DO',
      'modbus_exception' => 'หัววัดปฏิเสธคำสั่ง ตรวจรีจิสเตอร์',
      _ => 'ยังไม่มีค่าจาก $source',
    };

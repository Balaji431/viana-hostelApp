<?php
header('Access-Control-Allow-Origin: *');
header("Content-Type: application/json");
error_reporting(0);
ini_set('display_errors', 0);

require_once("../../config/database.php");

try {
    $db = new Database();
    $conn = $db->getConnection();
    
    $data = [];
    
    $hostels = $conn->query("SELECT * FROM hostels");
    
    while ($h = $hostels->fetch(PDO::FETCH_ASSOC)) {
        $zonesArr = [];
        $zones = $conn->query("SELECT * FROM zones WHERE hostel_id=".$h['id']);
        
        while ($z = $zones->fetch(PDO::FETCH_ASSOC)) {
            $subArr = [];
            $subs = $conn->query("SELECT * FROM sub_zones WHERE zone_id=".$z['id']);
            
            while ($s = $subs->fetch(PDO::FETCH_ASSOC)) {
                $roomsArr = [];
                $rooms = $conn->query("SELECT * FROM rooms WHERE sub_zone_id=".$s['id']);
                
                while ($r = $rooms->fetch(PDO::FETCH_ASSOC)) {
                    $roomsArr[] = $r;
                }
                
                $s['rooms'] = $roomsArr;
                $subArr[] = $s;
            }
            
            $z['subZones'] = $subArr;
            $zonesArr[] = $z;
        }
        
        $h['zones'] = $zonesArr;
        $data[] = $h;
    }
    
    echo json_encode([
        "success" => true,
        "data" => $data
    ]);
    
} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "error" => $e->getMessage()
    ]);
}
?>

<?php
header('Access-Control-Allow-Origin: *');
header('Content-Type: application/json');

require_once 'config/database.php';

try {
    $db = new Database();
    $conn = $db->getConnection();
    
    $results = [];

    // 1. Get all from hostel_type
    $stmt = $conn->query("SELECT hostel_name FROM hostel_type");
    $hostelTypes = [];
    while($row = $stmt->fetch_assoc()) {
        $hostelTypes[] = $row['hostel_name'];
    }
    
    // 2. Get all from hostels
    $stmt = $conn->query("SELECT name FROM hostels");
    $hostels = [];
    while($row = $stmt->fetch_assoc()) {
        $hostels[] = $row['name'];
    }
    
    $results['before'] = [
        'hostel_type_count' => count($hostelTypes),
        'hostels_count' => count($hostels)
    ];
    
    // Sync: If it's in hostel_type but not in hostels, add it
    foreach ($hostelTypes as $name) {
        if (!in_array($name, $hostels)) {
            $stmt = $conn->prepare("INSERT INTO hostels (name) VALUES (?)");
            $stmt->bind_param("s", $name);
            $stmt->execute();
            $results['actions'][] = "Added to hostels: $name";
        }
    }
    
    // Sync: If it's in hostels but not in hostel_type, remove it
    foreach ($hostels as $name) {
        if (!in_array($name, $hostelTypes)) {
            $stmt = $conn->prepare("DELETE FROM hostels WHERE name = ?");
            $stmt->bind_param("s", $name);
            $stmt->execute();
            $results['actions'][] = "Removed from hostels (not in hostel_type): $name";
        }
    }
    
    // 3. Final counts
    $stmt = $conn->query("SELECT COUNT(*) as count FROM hostels");
    $row = $stmt->fetch_assoc();
    $results['after'] = [
        'hostels_count' => (int)$row['count']
    ];

    echo json_encode([
        "success" => true,
        "message" => "Sync completed successfully",
        "data" => $results
    ]);

} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "message" => "Error: " . $e->getMessage()
    ]);
}
?>

<?php
header('Content-Type: text/plain; charset=UTF-8');

require_once 'hostel_backend/config/database.php';

$database = new Database();
$db = $database->getConnection();

echo "=== FIXING CHAT COLUMNS TO VARCHAR ===\n\n";

// Step 1: Convert sender_id to VARCHAR
echo "1. Converting sender_id to VARCHAR...\n";
try {
    $db->query("ALTER TABLE chat_messages MODIFY COLUMN sender_id VARCHAR(50)");
    echo "   ? sender_id converted to VARCHAR(50)\n";
} catch (Exception $e) {
    echo "   ? Error converting sender_id: " . $e->getMessage() . "\n";
}

// Step 2: Convert receiver_id to VARCHAR
echo "\n2. Converting receiver_id to VARCHAR...\n";
try {
    $db->query("ALTER TABLE chat_messages MODIFY COLUMN receiver_id VARCHAR(50)");
    echo "   ? receiver_id converted to VARCHAR(50)\n";
} catch (Exception $e) {
    echo "   ? Error converting receiver_id: " . $e->getMessage() . "\n";
}

// Step 3: Verify structure
echo "\n3. Verifying new structure...\n";
$stmt = $db->query("DESCRIBE chat_messages");
$columns = $stmt->fetchAll(PDO::FETCH_ASSOC);

echo "   Updated table structure:\n";
foreach ($columns as $col) {
    if (in_array($col['Field'], ['sender_id', 'receiver_id'])) {
        echo "   {$col['Field']}: {$col['Type']}\n";
    }
}

// Step 4: Clean up existing data
echo "\n4. Cleaning up existing data...\n";
$stmt = $db->query("SELECT id, sender_id, receiver_id FROM chat_messages WHERE sender_id IS NULL OR receiver_id IS NULL OR sender_id = '' OR receiver_id = ''");
$problematic = $stmt->fetchAll(PDO::FETCH_ASSOC);

if (count($problematic) > 0) {
    echo "   Found " . count($problematic) . " problematic records\n";
    
    // Delete problematic records
    $db->query("DELETE FROM chat_messages WHERE sender_id IS NULL OR receiver_id IS NULL OR sender_id = '' OR receiver_id = ''");
    echo "   ? Deleted problematic records\n";
} else {
    echo "   ? No problematic records found\n";
}

echo "\n=== COLUMN FIX COMPLETE ===\n";
echo "\nTable is now ready for username-based sender_id and receiver_id\n";
?>
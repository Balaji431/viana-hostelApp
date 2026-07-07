<?php
// cron.php or expire_holds.php
require_once __DIR__ . '/../config/database.php';

$database = new DatabaseMysqli();
$conn = $database->getConnection();

function log_msg($msg) {
    if (php_sapi_name() === 'cli' || !isset($_SERVER['REQUEST_METHOD'])) {
        echo $msg . "\n";
    }
}

log_msg("Starting hold expiration check at " . date('Y-m-d H:i:s'));

$conn->begin_transaction();

try {
    // 1. Release expired holds in hostel_rooms (Clean up legacy explorer blocks)
    $release_rooms = "
        UPDATE hostel_rooms r
        JOIN allocation_requests a ON a.selected_room_id = r.id
        SET r.blocked_by = NULL, r.blocked_until = NULL
        WHERE a.status = 'payment_pending' 
        AND a.payment_deadline < NOW()
    ";
    $conn->query($release_rooms);
    $affected_rooms = $conn->affected_rows;
    log_msg("Released $affected_rooms legacy room blocks.");

    // 2. Fetch all expired allocations
    $expired_query = "SELECT id, student_id, selected_room_id FROM allocation_requests 
                      WHERE status = 'payment_pending' AND payment_deadline < NOW()";
    $exp_res = $conn->query($expired_query);
    
    $expired_allocations = [];
    if ($exp_res) {
        while ($row = $exp_res->fetch_assoc()) {
            $expired_allocations[] = $row;
        }
    }
    
    log_msg("Found " . count($expired_allocations) . " expired allocations.");
    
    foreach ($expired_allocations as $alloc) {
        $alloc_id = (int)$alloc['id'];
        $student_id = (int)$alloc['student_id'];
        $old_room_id = (int)$alloc['selected_room_id'];
        
        log_msg("Processing expired allocation ID $alloc_id for Student ID $student_id (Old Room: $old_room_id)");
        
        // Find priority of the old room in user's preferences
        $pri_query = "SELECT priority_order FROM room_preferences WHERE student_id = ? AND room_id = ? LIMIT 1";
        $pri_stmt = $conn->prepare($pri_query);
        $pri_stmt->bind_param("ii", $student_id, $old_room_id);
        $pri_stmt->execute();
        $pri_row = $pri_stmt->get_result()->fetch_assoc();
        $current_priority = $pri_row ? (int)$pri_row['priority_order'] : 0;
        
        // Fetch all remaining preferences with a higher priority order (i.e. P2, P3, etc.)
        $pref_query = "SELECT rp.room_id, rp.priority_order, hr.room_no, hr.total_capacity, hr.occupied_rooms 
                       FROM room_preferences rp
                       JOIN hostel_rooms hr ON rp.room_id = hr.id
                       WHERE rp.student_id = ? AND rp.priority_order > ?
                       ORDER BY rp.priority_order ASC";
        $pref_stmt = $conn->prepare($pref_query);
        $pref_stmt->bind_param("ii", $student_id, $current_priority);
        $pref_stmt->execute();
        $pref_res = $pref_stmt->get_result();
        
        $transitioned = false;
        
        while ($pref = $pref_res->fetch_assoc()) {
            $new_room_id = (int)$pref['room_id'];
            $room_no = $pref['room_no'];
            $capacity = (int)$pref['total_capacity'];
            $occupied = (int)$pref['occupied_rooms'];
            
            // Check active holds in this next preference room
            $hold_query = "SELECT COUNT(*) as hold_count FROM allocation_requests 
                           WHERE selected_room_id = ? AND status = 'payment_pending' AND payment_deadline > NOW()";
            $hold_stmt = $conn->prepare($hold_query);
            $hold_stmt->bind_param("i", $new_room_id);
            $hold_stmt->execute();
            $hold_count = $hold_stmt->get_result()->fetch_assoc()['hold_count'];
            
            if (($occupied + $hold_count) < $capacity) {
                // Next room has capacity! Transition student automatically!
                log_msg("Transitioning student $student_id automatically to next priority Room $room_no (ID $new_room_id, P{$pref['priority_order']})");
                
                $now = new DateTime();
                $deadline = clone $now;
                $deadline->modify('+24 hours');
                $deadline_str = $deadline->format('Y-m-d H:i:s');
                $now_str = $now->format('Y-m-d H:i:s');
                
                $up_query = "UPDATE allocation_requests 
                             SET selected_room_id = ?, 
                                 status = 'payment_pending', 
                                 request_status = 'approved',
                                 payment_deadline = ?,
                                 approved_by = 1,
                                 approved_at = ?,
                                 notified_of_conflict = 0
                             WHERE id = ?";
                $up_stmt = $conn->prepare($up_query);
                $up_stmt->bind_param("issi", $new_room_id, $deadline_str, $now_str, $alloc_id);
                $up_stmt->execute();
                
                $transitioned = true;
                break;
            } else {
                log_msg("Next priority Room $room_no is full. Checking further preferences.");
            }
        }
        
        if (!$transitioned) {
            // No next preferences available or all of them are occupied. Expire request fully.
            log_msg("No remaining preferences available. Expiring allocation completely.");
            
            $expire_query = "UPDATE allocation_requests 
                             SET status = 'payment_expired', request_status = 'cancelled' 
                             WHERE id = ?";
            $expire_stmt = $conn->prepare($expire_query);
            $expire_stmt->bind_param("i", $alloc_id);
            $expire_stmt->execute();
            
            // Cancel remaining preferences
            $cancel_query = "UPDATE room_preferences SET status = 'cancelled' WHERE student_id = ? AND status = 'submitted'";
            $cancel_stmt = $conn->prepare($cancel_query);
            $cancel_stmt->bind_param("i", $student_id);
            $cancel_stmt->execute();
        }
    }

    $conn->commit();
    log_msg("Check completed successfully.");

} catch (Exception $e) {
    $conn->rollback();
    log_msg("ERROR: " . $e->getMessage());
}
?>

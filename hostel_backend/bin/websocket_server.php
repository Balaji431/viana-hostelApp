<?php
/**
 * VStay Real-Time WebSocket Server (PHP Workerman)
 * 
 * Provides sub-second real-time chat message delivery to Flutter Web, Android, and iOS clients.
 * Subscribes to Redis channel 'vstay_chat_events' triggered by send_message.php.
 */

require_once __DIR__ . '/../vendor/autoload.php';

use Workerman\Worker;
use Workerman\Connection\TcpConnection;
use Workerman\Lib\Timer;

// Create WebSocket worker listening on internal port 3001
$ws_worker = new Worker("websocket://0.0.0.0:3001");
$ws_worker->count = 1; // Single process maintains unified in-memory room mapping
$ws_worker->name = 'VStayWebSocket';

// In-memory mapping of rooms and users
$ws_worker->rooms = [];       // room_name => [connection_id => connection]
$ws_worker->user_conns = [];  // username => [connection_id => connection]
$ws_worker->conn_users = [];  // connection_id => username

$ws_worker->onWorkerStart = function($worker) {
    echo "[" . date('Y-m-d H:i:s') . "] VStay WebSocket daemon started on port 3001\n";

    $redis_host = getenv('REDIS_HOST') ?: 'redis';
    $redis_port = (int)(getenv('REDIS_PORT') ?: 6379);

    // Run non-blocking Redis subscription loop using pure PHP sockets
    $subscribe_redis = function() use ($worker, $redis_host, $redis_port, &$subscribe_redis) {
        try {
            $socket = @fsockopen($redis_host, $redis_port, $errno, $errstr, 3);
            if (!$socket) {
                echo "[" . date('Y-m-d H:i:s') . "] Redis connection failed: $errstr. Retrying in 3s...\n";
                Timer::add(3, $subscribe_redis, [], false);
                return;
            }

            stream_set_blocking($socket, false);
            // Send Redis SUBSCRIBE command using standard RESP protocol
            fwrite($socket, "*2\r\n$9\r\nSUBSCRIBE\r\n$17\r\nvstay_chat_events\r\n");

            echo "[" . date('Y-m-d H:i:s') . "] Successfully subscribed to Redis channel: vstay_chat_events\n";

            // Attach read event loop to the socket using Workerman globalEvent
            if (\Workerman\Worker::$globalEvent) {
                \Workerman\Worker::$globalEvent->add($socket, \Workerman\Events\EventInterface::EV_READ, function($socket) use ($worker, $subscribe_redis) {
                    $buffer = '';
                    while ($chunk = @fread($socket, 8192)) {
                        $buffer .= $chunk;
                    }

                    if ($buffer === '' && feof($socket)) {
                        echo "[" . date('Y-m-d H:i:s') . "] Redis socket closed. Reconnecting...\n";
                        if (\Workerman\Worker::$globalEvent) {
                            \Workerman\Worker::$globalEvent->del($socket, \Workerman\Events\EventInterface::EV_READ);
                        }
                        @fclose($socket);
                        Timer::add(3, $subscribe_redis, [], false);
                        return;
                    }

                    // Extract and decode all complete JSON objects from Redis stream buffer
                    $json_list = extractJsonFromStream($buffer);
                    if (!empty($json_list)) {
                        $t3_ws_redis_received = (int)round(microtime(true) * 1000);
                        foreach ($json_list as $json_str) {
                            $event = json_decode($json_str, true);
                            if ($event && isset($event['event'])) {
                                if (!isset($event['timings'])) $event['timings'] = [];
                                $event['timings']['t3_ws_redis_received_ms'] = $t3_ws_redis_received;
                                broadcastEventToClients($worker, $event);
                            }
                        }
                    }
                });
            }
        } catch (\Throwable $e) {
            echo "[" . date('Y-m-d H:i:s') . "] Redis error: " . $e->getMessage() . ". Retrying...\n";
            Timer::add(3, $subscribe_redis, [], false);
        }
    };

    $subscribe_redis();
};

/**
 * Extract complete JSON objects from a stream buffer supporting nested braces and quotes
 */
function extractJsonFromStream($str) {
    $objs = [];
    $len = strlen($str);
    $depth = 0;
    $start = -1;
    $inStr = false;
    $esc = false;

    for ($i = 0; $i < $len; $i++) {
        $c = $str[$i];
        if ($inStr) {
            if ($esc) {
                $esc = false;
            } elseif ($c === '\\') {
                $esc = true;
            } elseif ($c === '"') {
                $inStr = false;
            }
            continue;
        }

        if ($c === '"') {
            $inStr = true;
            continue;
        }

        if ($c === '{') {
            if ($depth === 0) {
                $start = $i;
            }
            $depth++;
        } elseif ($c === '}') {
            $depth--;
            if ($depth === 0 && $start !== -1) {
                $objs[] = substr($str, $start, $i - $start + 1);
                $start = -1;
            }
        }
    }
    return $objs;
}

/**
 * Broadcast an event received from Redis to connected clients
 */
function broadcastEventToClients($ws_worker, $event) {
    $request_id = $event['request_id'] ?? null;
    $receiver_id = $event['receiver_id'] ?? null;
    $msg_id = $event['message_id'] ?? $event['id'] ?? null;

    $t4_ws_socket_dispatched = (int)round(microtime(true) * 1000);
    $event['timings']['t4_ws_socket_dispatched_ms'] = $t4_ws_socket_dispatched;

    $payload = json_encode($event);
    $sent_count = 0;

    // Track which connection IDs already received this payload to avoid double-delivery
    // when a receiver is simultaneously a member of the room.
    $already_sent_conn_ids = [];

    // 1. Broadcast to room chat_{request_id}
    if ($request_id) {
        $room_key = "chat_" . $request_id;
        if (isset($ws_worker->rooms[$room_key])) {
            foreach ($ws_worker->rooms[$room_key] as $conn_id => $conn) {
                $conn->send($payload);
                $already_sent_conn_ids[$conn_id] = true;
                $sent_count++;
            }
        }
    }

    // 2. Broadcast directly to receiver user if connected and NOT already reached via room
    if ($receiver_id && isset($ws_worker->user_conns[$receiver_id])) {
        foreach ($ws_worker->user_conns[$receiver_id] as $conn_id => $conn) {
            if (!isset($already_sent_conn_ids[$conn_id])) {
                $conn->send($payload);
                $sent_count++;
            }
        }
    }

    $t0 = $event['timings']['t0_http_received_ms'] ?? null;
    $t1 = $event['timings']['t1_db_inserted_ms'] ?? null;
    $t2 = $event['timings']['t2_redis_published_ms'] ?? null;
    $t3 = $event['timings']['t3_ws_redis_received_ms'] ?? null;
    $t4 = $t4_ws_socket_dispatched;

    $breakdown = "";
    if ($t0 && $t1 && $t2 && $t3) {
        $breakdown = sprintf(
            " [DB: %dms | RedisPub: %dms | RedisTransit: %dms | WSDispatch: %dms | ServerTotal: %dms]",
            ($t1 - $t0),
            ($t2 - $t1),
            ($t3 - $t2),
            ($t4 - $t3),
            ($t4 - $t0)
        );
    }

    $log_level = strtolower(getenv('LOG_LEVEL') ?: 'debug');
    if ($log_level !== 'error' && $log_level !== 'quiet' && $log_level !== 'production') {
        echo "[" . date('Y-m-d H:i:s') . "] [TIMING] Pushed event msg_id=$msg_id to $sent_count clients (Req: $request_id, Recv: $receiver_id)$breakdown\n";
    }
}


$ws_worker->onConnect = function(TcpConnection $connection) {
    // Initial connection opened
};

$ws_worker->onMessage = function(TcpConnection $connection, $data) use ($ws_worker) {
    $msg = json_decode($data, true);
    if (!$msg || !isset($msg['action'])) {
        return;
    }

    $action = $msg['action'];
    $conn_id = $connection->id;
    $log_level = strtolower(getenv('LOG_LEVEL') ?: 'debug');

    switch ($action) {
        case 'auth':
            $username = $msg['username'] ?? '';
            $token = $msg['token'] ?? '';
            if (!empty($username)) {
                $ws_worker->user_conns[$username][$conn_id] = $connection;
                $ws_worker->conn_users[$conn_id] = $username;
                $connection->send(json_encode([
                    'event' => 'authenticated',
                    'username' => $username,
                    'status' => 'success'
                ]));
                if ($log_level === 'debug') {
                    echo "[" . date('Y-m-d H:i:s') . "] User authenticated: $username (Conn #$conn_id)\n";
                }
            }
            break;

        case 'join_room':
            $room = $msg['room'] ?? '';
            if (!empty($room)) {
                $already_in_room = isset($ws_worker->rooms[$room][$conn_id]);
                $ws_worker->rooms[$room][$conn_id] = $connection;
                if ($already_in_room) {
                    // Silently re-confirm without logging noise; client-side idempotency
                    // should prevent this but handle gracefully if it slips through.
                    $connection->send(json_encode([
                        'event'  => 'joined_room',
                        'room'   => $room,
                        'status' => 'already_joined',
                    ]));
                } else {
                    $connection->send(json_encode([
                        'event'  => 'joined_room',
                        'room'   => $room,
                        'status' => 'success',
                    ]));
                    if ($log_level === 'debug') {
                        echo "[" . date('Y-m-d H:i:s') . "] Conn #$conn_id joined room: $room\n";
                    }
                }
            }
            break;

        case 'leave_room':
            $room = $msg['room'] ?? '';
            if (!empty($room) && isset($ws_worker->rooms[$room][$conn_id])) {
                unset($ws_worker->rooms[$room][$conn_id]);
                if (empty($ws_worker->rooms[$room])) {
                    unset($ws_worker->rooms[$room]);
                }
                if ($log_level === 'debug') {
                    echo "[" . date('Y-m-d H:i:s') . "] Conn #$conn_id left room: $room\n";
                }
            }
            break;

        case 'ping':
            $connection->send(json_encode(['event' => 'pong', 'timestamp' => time()]));
            break;

        case 'health':
            $connection->send(json_encode([
                'event' => 'health',
                'status' => 'healthy',
                'connections' => count($ws_worker->conn_users),
                'rooms' => count($ws_worker->rooms)
            ]));
            break;
    }
};

$ws_worker->onClose = function(TcpConnection $connection) use ($ws_worker) {
    $conn_id = $connection->id;

    // Clean up room memberships
    foreach ($ws_worker->rooms as $room => $conns) {
        if (isset($conns[$conn_id])) {
            unset($ws_worker->rooms[$room][$conn_id]);
            if (empty($ws_worker->rooms[$room])) {
                unset($ws_worker->rooms[$room]);
            }
        }
    }

    // Clean up user connection
    if (isset($ws_worker->conn_users[$conn_id])) {
        $username = $ws_worker->conn_users[$conn_id];
        if (isset($ws_worker->user_conns[$username][$conn_id])) {
            unset($ws_worker->user_conns[$username][$conn_id]);
            if (empty($ws_worker->user_conns[$username])) {
                unset($ws_worker->user_conns[$username]);
            }
        }
        unset($ws_worker->conn_users[$conn_id]);
    }
};

// Run all workers
Worker::runAll();

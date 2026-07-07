<?php
ob_start();
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    exit(0);
}

require_once '../config/api_config.php';
require_once '../utils/fpdf.php';

class HostelPDF extends FPDF {
    // Page header
    function Header() {
        $this->SetFont('Arial', 'B', 15);
        $this->SetTextColor(26, 39, 68); // #1A2744 (Navy)
        $this->Cell(0, 10, 'VIANA HOSTEL - FEE AVAILABILITY LIST', 0, 1, 'C');
        $this->SetFont('Arial', 'I', 9);
        $this->SetTextColor(128, 128, 128);
        $this->Cell(0, 5, 'Hostels with Hostel Fee Below 50,000 (Excluding Food & Caution Deposit)', 0, 1, 'C');
        $this->Ln(10);
        
        // Table Header
        $this->SetFont('Arial', 'B', 9);
        $this->SetFillColor(26, 39, 68);
        $this->SetTextColor(255, 255, 255);
        $this->Cell(45, 8, 'Hostel Name', 1, 0, 'L', true);
        $this->Cell(65, 8, 'Room Type', 1, 0, 'L', true);
        $this->Cell(20, 8, 'Hostel Fee', 1, 0, 'R', true);
        $this->Cell(20, 8, 'Food Fee', 1, 0, 'R', true);
        $this->Cell(20, 8, 'Caution Dep.', 1, 0, 'R', true);
        $this->Cell(20, 8, 'Total Fee', 1, 1, 'R', true);
    }

    // Page footer
    function Footer() {
        $this->SetY(-15);
        $this->SetFont('Arial', 'I', 8);
        $this->SetTextColor(128, 128, 128);
        $this->Cell(0, 10, 'Page ' . $this->PageNo() . ' / {nb} | Generated on: ' . date('Y-m-d H:i:s'), 0, 0, 'C');
    }
}

try {
    $externalApiUrl = 'https://vstudy.saveetha.com/api/hostel-settings/availability/external';
    
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $externalApiUrl);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 30);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'x-client-id: ' . VSTUDY_CLIENT_ID,
        'x-client-secret: ' . VSTUDY_CLIENT_SECRET
    ]);
    
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    
    if ($httpCode !== 200 || !$response) {
        throw new Exception("Failed to fetch data from external API (HTTP $httpCode)");
    }
    
    $data = json_decode($response, true);
    $rawList = isset($data['data']) ? $data['data'] : (is_array($data) ? $data : []);
    
    $filtered = [];
    foreach ($rawList as $item) {
        if (is_array($item) && isset($item['amount']) && isset($item['roomType'])) {
            if ($item['amount'] < 50000) {
                $filtered[] = $item;
            }
        }
    }
    
    // Sort by Hostel Name, then Amount
    usort($filtered, function($a, $b) {
        $hostelCmp = strcmp($a['hostelName'], $b['hostelName']);
        if ($hostelCmp !== 0) return $hostelCmp;
        return $a['amount'] - $b['amount'];
    });
    
    // Initialize PDF
    $pdf = new HostelPDF('P', 'mm', 'A4');
    $pdf->AliasNbPages();
    $pdf->AddPage();
    $pdf->SetFont('Arial', '', 9);
    
    $fill = false;
    foreach ($filtered as $row) {
        $pdf->SetFillColor(245, 245, 245);
        $pdf->SetTextColor(0, 0, 0);
        
        $hostelName = $row['hostelName'];
        $roomType = $row['roomType'];
        $hostelFee = (float)$row['amount'];
        $foodFee = (float)($row['food'] ?? 0);
        $caution = (float)($row['cautionDeposit'] ?? 0);
        $total = $hostelFee + $foodFee + $caution;
        
        $pdf->Cell(45, 7, $hostelName, 1, 0, 'L', $fill);
        $pdf->Cell(65, 7, $roomType, 1, 0, 'L', $fill);
        $pdf->Cell(20, 7, number_format($hostelFee, 0), 1, 0, 'R', $fill);
        $pdf->Cell(20, 7, number_format($foodFee, 0), 1, 0, 'R', $fill);
        $pdf->Cell(20, 7, number_format($caution, 0), 1, 0, 'R', $fill);
        $pdf->Cell(20, 7, number_format($total, 0), 1, 1, 'R', $fill);
        
        $fill = !$fill; // Alternate background colors
    }
    
    // Clear any previous output or whitespace sent by included files
    if (ob_get_length()) {
        ob_clean();
    }
    
    // Output PDF to browser for inline viewing/download
    $pdf->Output('I', 'hostel_fees_below_50000.pdf');
    exit(0);
    
} catch (Exception $e) {
    if (ob_get_length()) {
        ob_clean();
    }
    header("Content-Type: text/html");
    echo "<h3>Error generating PDF: " . htmlspecialchars($e->getMessage()) . "</h3>";
}
?>

<?php
$filepath = 'C:/Users/daset/Downloads/stay_simats (10).sql';
$content = @file_get_contents($filepath);

if ($content === false) {
    echo "ERROR: Could not read $filepath\n";
    exit(1);
}

$target = "(1114, 192524101, 'present', '2026-05-29 09:18:22', 'warden', 'manual'),";
$replacement = "(1114, 192524101, 'present', '2026-05-29 09:18:22', 'warden', 'manual');";

if (strpos($content, $target) !== false) {
    $content = str_replace($target, $replacement, $content);
    if (file_put_contents($filepath, $content) !== false) {
        echo "SUCCESS: Replaced trailing comma with semicolon in Downloads folder file.\n";
        
        // Also copy it over to the Desktop path the user specified
        $desktopPath = 'C:/Users/daset/OneDrive/Desktop/stay_simats (10).sql';
        if (copy($filepath, $desktopPath)) {
            echo "SUCCESS: Copied fixed SQL file to Desktop: $desktopPath\n";
        } else {
            echo "WARNING: Could not copy to Desktop. Please use the one in Downloads folder.\n";
        }
    } else {
        echo "ERROR: Could not write fixed content back to $filepath\n";
    }
} else {
    echo "ERROR: Target string not found in SQL file.\n";
}
?>

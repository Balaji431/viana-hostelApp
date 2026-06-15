<?php
$filepath = 'C:/Users/daset/Downloads/stay_simats (10).sql';
$content = @file_get_contents($filepath);

if ($content === false) {
    echo "ERROR: Could not read $filepath\n";
    exit(1);
}

// Regex to find "CREATE TABLE `table_name`" and prepend "DROP TABLE IF EXISTS `table_name`;"
$pattern = '/CREATE TABLE `([a-zA-Z0-9_]+)`/i';
$replacement = 'DROP TABLE IF EXISTS `$1`;' . "\n" . 'CREATE TABLE `$1`';

$new_content = preg_replace($pattern, $replacement, $content);

if ($new_content !== null && $new_content !== $content) {
    if (file_put_contents($filepath, $new_content) !== false) {
        echo "SUCCESS: Added DROP TABLE IF EXISTS statements in Downloads folder file.\n";
        
        // Also copy it over to the Desktop path
        $desktopPath = 'C:/Users/daset/OneDrive/Desktop/stay_simats (10).sql';
        if (copy($filepath, $desktopPath)) {
            echo "SUCCESS: Copied updated SQL file to Desktop: $desktopPath\n";
        } else {
            echo "WARNING: Could not copy to Desktop. Please use the one in Downloads folder.\n";
        }
    } else {
        echo "ERROR: Could not write updated content to $filepath\n";
    }
} else {
    echo "ERROR: No CREATE TABLE statements found or replacement failed.\n";
}
?>

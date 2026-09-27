<?php

declare(strict_types=1);

/**
 * Generates docs/Frontend_Developer_Handoff.pdf from docs/Frontend_Developer_Handoff.html
 * Run: php scripts/generate_frontend_handoff_pdf.php
 */

require dirname(__DIR__).'/vendor/autoload.php';

if (! class_exists(\Dompdf\Dompdf::class)) {
    fwrite(STDERR, "Install Dompdf first: composer require dompdf/dompdf\n");
    exit(1);
}

use Dompdf\Dompdf;
use Dompdf\Options;

$htmlPath = dirname(__DIR__).'/docs/Frontend_Developer_Handoff.html';
$pdfPath = dirname(__DIR__).'/docs/Frontend_Developer_Handoff.pdf';

if (! is_readable($htmlPath)) {
    fwrite(STDERR, "Missing HTML file: {$htmlPath}\n");
    exit(1);
}

$options = new Options;
$options->set('isRemoteEnabled', false);
$options->set('defaultFont', 'DejaVu Sans');

$dompdf = new Dompdf($options);
$dompdf->loadHtml(file_get_contents($htmlPath));
$dompdf->setPaper('A4', 'portrait');
$dompdf->render();

file_put_contents($pdfPath, $dompdf->output());

echo "Created: {$pdfPath}\n";

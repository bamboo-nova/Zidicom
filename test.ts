import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import DicomWasm from './dicom-wasm.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
  console.log('DICOM WASM Test Script');
  console.log('======================\n');

  // Initialize WASM
  console.log('1. Initializing WASM module...');
  const dicomWasm = new DicomWasm();
  await dicomWasm.init();
  console.log('   ✓ WASM module initialized\n');

  // Test basic function
  console.log('2. Testing basic WASM function...');
  const sum = dicomWasm.testAdd(42, 8);
  console.log(`   testAdd(42, 8) = ${sum}`);
  console.log(`   ✓ Test ${sum === 50 ? 'PASSED' : 'FAILED'}\n`);

  // Find DICOM files
  console.log('3. Searching for DICOM files...');
  const files = fs.readdirSync(path.join(__dirname, '..'))
    .filter(f => f.endsWith('.dcm'));

  if (files.length === 0) {
    console.log('   ! No DICOM files found in current directory\n');
    console.log('To test with a DICOM file, place a .dcm file in the project directory.');
    return;
  }

  console.log(`   Found ${files.length} DICOM file(s):\n`);
  files.forEach(f => console.log(`   - ${f}`));
  console.log('');

  // Process first DICOM file
  const testFile = files[0];
  console.log(`4. Processing ${testFile}...`);
  const filePath = path.join(__dirname, '..', testFile);
  const fileSize = fs.statSync(filePath).size;
  console.log(`   File size: ${(fileSize / 1024 / 1024).toFixed(2)} MB`);

  const dicomBuffer = new Uint8Array(fs.readFileSync(filePath));

  // Get dimensions
  console.log('\n5. Extracting image dimensions...');
  try {
    const dimensions = await dicomWasm.getDimensions(dicomBuffer);
    console.log(`   Width: ${dimensions.width} px`);
    console.log(`   Height: ${dimensions.height} px`);
    console.log(`   Total pixels: ${(dimensions.width * dimensions.height).toLocaleString()}`);
    console.log('   ✓ Dimensions extracted successfully\n');
  } catch (error) {
    console.log(`   ✗ Failed to get dimensions: ${error}\n`);
  }

  // Get metadata
  console.log('6. Extracting metadata...');
  try {
    const metadata = await dicomWasm.extractMetadata(dicomBuffer);
    console.log('   Metadata:');
    Object.entries(metadata).forEach(([key, value]) => {
      console.log(`   - ${key}: ${value}`);
    });
    console.log('   ✓ Metadata extracted successfully\n');
  } catch (error) {
    console.log(`   ✗ Failed to get metadata: ${error}\n`);
  }

  // Memory stats
  console.log('7. Memory statistics:');
  const memoryUsed = dicomWasm.getMemoryStats();
  console.log(`   WASM memory used: ${(memoryUsed / 1024).toFixed(2)} KB\n`);

  console.log('======================');
  console.log('Test completed!');
}

main().catch(console.error);

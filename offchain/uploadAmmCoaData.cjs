const csvParser = require('csv-parser');
const fs = require('fs');
const pg = require('pg');
const dotenv = require('dotenv');
const BigNumber = require('bignumber.js');
dotenv.config();

const client = new pg.Client({
    user: process.env.DB_USER,
    host: process.env.DB_HOST,
    database: process.env.DB_NAME,
    password: process.env.DB_PASSWORD,
    port: process.env.DB_PORT,
    ssl: true,
});

const csvFilePath = process.env.FILE_PATH;

async function processData() {
    console.log('Connecting to database...')
    await client.connect(err => {
        if (err) throw err;
        else {
            console.log('Connected to database.');
            writeDb();
        }
    });
}

async function writeDb() {
    const currentTime = Math.floor(Date.now() / 1000);
    const rows = [];

    fs.createReadStream(csvFilePath)
        .pipe(csvParser())
        .on('data', async (row) => {
            const { amountSpecified, oldPrice, newPrice, swapReceived } = row;

            // cast all values to float then divide by 1e18)
            const as = new BigNumber(amountSpecified).dividedBy(1e18).toNumber();
            const op = new BigNumber(oldPrice).dividedBy(1e18).toNumber();
            const np = new BigNumber(newPrice).dividedBy(1e18).toNumber();
            const sr = new BigNumber(swapReceived).dividedBy(1e18).toNumber();
            // console.log(amountSpecified, oldPrice, newPrice, swapReceived)
            // console.log(as, op, np, sr)

            const market = 'swETH';
            const amm = 'Uniswap';

            const query = {
                text: `INSERT INTO amm_cost_of_attack_data (old_price, new_price, swap_received, eth_sent, market, amm_provider, timestamp)
                        VALUES ($1, $2, $3, $4, $5, $6, $7)`,
                values: [op, np, sr, as, market, amm, currentTime],
            };

            rows.push(client.query(query));
        })
        .on('end', async () => {
            try {
                await Promise.all(rows); // Wait for all insert queries to complete
                console.log(`All ${rows.length} rows inserted successfully.`);
                clearFileContents(csvFilePath);
            } catch (error) {
                console.error('Error inserting rows:', error);
            } finally {
                client.end(); // Close the database connection after processing is complete
            }
        });
    
}

function clearFileContents(filePath) {
    // Open the file in write mode and truncate its contents
    fs.writeFileSync(filePath, '', 'utf8');
    console.log(`Contents of file at ${filePath} cleared successfully.`);
}

processData();
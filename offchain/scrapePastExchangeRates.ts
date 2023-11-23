import { createPublicClient, http } from "viem";
import { mainnet, goerli } from "viem/chains";
import { format, subDays } from "date-fns";
import dotenv from "dotenv";
dotenv.config();

const LOOK_BACK = 7;

// CHAIN_ID = 31337 is also possible but this should always be a mainnet fork
// and should thus always use the mainnet addresses

const CHAIN_ID = process.env.CHAIN_ID! as "1" | "5";
const CHAIN = CHAIN_ID == "5" ? goerli : mainnet;
const ETHERSCAN_URL =
  CHAIN_ID! == "5"
    ? process.env.GOERLI_ETHERSCAN_URL
    : process.env.MAINNET_ETHERSCAN_URL;
const RPC_URL = 
  CHAIN_ID == "5" ? process.env.GOERLI_ARCHIVE : process.env.MAINNET_ARCHIVE;

const exchangeRateAddresses = {
  lido: {
    "1": "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0",
    "5": "0x6320cD32aA674d2898A68ec82e869385Fc5f7E2f",
  },
  stader: {
    "1": "0xcf5EA1b38380f6aF39068375516Daf40Ed70D299",
    "5": "0x22F8E700ff3912f3Caba5e039F6dfF1a24390E80",
  },
  swell: {
    "1": "0xf951E335afb289353dc249e82926178EaC7DEd78",
    "5": "0x8bb383A752Ff3c1d510625C6F536E3332327068F",
  },
};

async function main() {
  // Set up RPC provider
  const transport = http(`${RPC_URL}`);

  const client = createPublicClient({
    transport,
    chain: CHAIN,
  });

  const getBlockDataFromTimestamp = async (timestamp: number) => {
    // Get around rate limit
    await new Promise((res, _) => setTimeout(res, 200));
    const etherscanApiUrl = `${ETHERSCAN_URL}?module=block&action=getblocknobytime&timestamp=${timestamp}&closest=before&apikey=${process.env.ETHERSCAN_API_KEY}`;

    const blockResult = await fetch(etherscanApiUrl);

    let blockNumber;
    let blockTimestamp;
    const blockRes = await blockResult.json();
    if (blockRes.status == "1") {
      blockNumber = blockRes.result;
      blockTimestamp = (await client.getBlock({ blockNumber })).timestamp;
    } else {
      const newestBlock = await client.getBlock();
      blockNumber = newestBlock.number.toString();
      blockTimestamp = newestBlock.timestamp;
    }

    return {
      timestamp: blockTimestamp,
      blockNumber,
    };
  };

  const exchangeRateContracts = {
    lido: {
      address: exchangeRateAddresses.lido[CHAIN_ID],
      abi: [
        {
          inputs: [],
          name: "stEthPerToken",
          outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
          stateMutability: "view",
          type: "function",
        },
      ],
    },
    stader: {
      address: exchangeRateAddresses.stader[CHAIN_ID],
      abi: [
        {
          inputs: [],
          name: "getExchangeRate",
          outputs: [
            {
              internalType: "uint256",
              type: "uint256",
            },
          ],
          stateMutability: "view",
          type: "function",
        },
      ],
    },
    swell: {
      address: exchangeRateAddresses.swell[CHAIN_ID],
      abi: [
        {
          inputs: [],
          name: "swETHToETHRate",
          outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
          stateMutability: "view",
          type: "function",
        },
      ],
    },
  };

  // If a third argument "x" is passed, run this scripts as if the current date
  // was "x" days ago. This will allow for historic simulations
  const warpDaysAmount = process.argv[2];

  const timeNow = new Date();

  // Set the current date and time in UTC
  let currentDateUTC = timeNow;
  if (warpDaysAmount) {
    currentDateUTC = subDays(currentDateUTC, Number(warpDaysAmount));
  }

  // Get the current hour in UTC
  const currentHourUTC = currentDateUTC.getUTCHours();

  // Calculate the most recent date that has passed 12:00 PM UTC
  let recentDateUTC;

  if (currentHourUTC < 12) {
    // If the current hour is before 12 PM UTC, subtract one day
    recentDateUTC = subDays(currentDateUTC, 1);
  } else {
    // If the current hour is 12 PM or later, keep it on the same day
    recentDateUTC = currentDateUTC;
  }

  // Set the time to 12:00 PM UTC
  recentDateUTC.setUTCHours(12, 0, 0, 0);

  const timestampInSeconds = Math.floor(recentDateUTC.getTime() / 1000);

  // We add one to get the next day's data as well.
  const relevantTimestamps = Array.from(
    { length: LOOK_BACK },
    (_, i) => timestampInSeconds - i * 86400
  ).reverse();

  const closestBlockData = [];
  for (let i = 0; i < relevantTimestamps.length; i++) {
    let blockData;
    try {
      blockData = await getBlockDataFromTimestamp(relevantTimestamps[i]);
    } catch (err) {
      console.error("Etherscan fetch error:", err);
    }

    closestBlockData.push(blockData);
  }

  const historicalExchangeRates: any = {};
  historicalExchangeRates["exchangeRateData"] = {};

  for (const key in exchangeRateContracts) {
    //@ts-ignore
    const { address, abi } = exchangeRateContracts[key];

    const exchangeRateData = await Promise.all(
      //@ts-ignore
      closestBlockData.map(async ({ blockNumber }) => {
        //@ts-ignore
        let returnData = await client.readContract({
          address: address as `0x${string}`,
          abi,
          functionName: abi[0].name,
          blockNumber,
        });

        let exchangeRate = returnData;

        return exchangeRate;
      })
    );

    historicalExchangeRates["exchangeRateData"][key] = {
      address,
      historicalExchangeRates: exchangeRateData,
    };
  }

  const formattedBlockData = closestBlockData.map(
    //@ts-ignore
    ({ timestamp, blockNumber }) => {
      return {
        humanTimestamp: format(
          new Date(Number(timestamp) * 1000),
          "yyyy-MM-dd HH:mm:ss"
        ),
        timestamp,
        blockNumber,
      };
    }
  );

  historicalExchangeRates["dailyBlockData"] = formattedBlockData;

  // If a warp simulation is being,
  if (warpDaysAmount) {
    let currentTimestamp = timestampInSeconds + 86400;
    historicalExchangeRates["nextDaysBlockData"] = {};
    historicalExchangeRates["nextDaysBlockData"]["blockNumbers"] = [];
    historicalExchangeRates["nextDaysBlockData"]["timestamps"] = [];

    while (currentTimestamp < Math.floor(timeNow.getTime() / 1000)) {
      const { blockNumber: nextDayBlockNumber, timestamp: nextDayTimestamp } =
        await getBlockDataFromTimestamp(currentTimestamp);

      historicalExchangeRates["nextDaysBlockData"]["blockNumbers"].push(
        nextDayBlockNumber
      );
      historicalExchangeRates["nextDaysBlockData"]["timestamps"].push(
        nextDayTimestamp
      );

      currentTimestamp += 86400;
    }
  }

  console.log(
    JSON.stringify(historicalExchangeRates, (_, v) =>
      typeof v === "bigint" ? v.toString() : v
    )
  );
}

main();

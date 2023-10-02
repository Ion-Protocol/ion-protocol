import { createPublicClient, http } from "viem";
import { mainnet, goerli } from "viem/chains";
import { format, subDays } from "date-fns";
import { sleep } from "bun";

const LOOK_BACK = 7;

async function main() {
  // Set up RPC provider
  const transport = http(`${Bun.env.RPC_URL}`);

  const client = createPublicClient({
    transport,
    chain: Bun.env.CHAIN_ID! == "1" ? mainnet : goerli,
  });

  const exchangeRateContracts = {
    lido: {
      address: "0x6320cD32aA674d2898A68ec82e869385Fc5f7E2f",
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
      address: "0x22F8E700ff3912f3Caba5e039F6dfF1a24390E80",
      abi: [
        {
          inputs: [],
          name: "exchangeRate",
          outputs: [
            {
              internalType: "uint256",
              name: "reportingBlockNumber",
              type: "uint256",
            },
            {
              internalType: "uint256",
              name: "totalETHBalance",
              type: "uint256",
            },
            {
              internalType: "uint256",
              name: "totalETHXSupply",
              type: "uint256",
            },
          ],
          stateMutability: "view",
          type: "function",
        },
      ],
    },
    swell: {
      address: "0x8bb383A752Ff3c1d510625C6F536E3332327068F",
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

  // Set the current date and time in UTC
  const currentDateUTC = new Date();

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

  const relevantTimestamps = Array.from(
    { length: LOOK_BACK },
    (_, i) => timestampInSeconds - i * 86400
  ).reverse();

  const closestBlockData = [];
  for (let i = 0; i < relevantTimestamps.length; i++) {
    const etherscanApiUrl = `${Bun.env.ETHERSCAN_URL}?module=block&action=getblocknobytime&timestamp=${relevantTimestamps[i]}&closest=before&apikey=${Bun.env.ETHERSCAN_API_KEY}`;

    let blockData;
    try {
      // Get around rate limit
      await sleep(200);
      const blockResult = await fetch(etherscanApiUrl);
      const blockNumber = (await blockResult.json()).result;
      const blockTimestamp = (await client.getBlock({ blockNumber })).timestamp;

      blockData = {
        blockNumber,
        timestamp: Number(blockTimestamp),
      };
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
      closestBlockData.map(async ({ timestamp, blockNumber }) => {
        let returnData = await client.readContract({
          address: address as `0x${string}`,
          abi,
          functionName: abi[0].name,
          blockNumber,
        });

        let exchangeRate;
        if (key == "stader") {
          //@ts-ignore
          const [, totalEthBalance, totalEthXSupply] = returnData;
          exchangeRate =
            (totalEthBalance * BigInt(10) ** BigInt(18)) / totalEthXSupply;
        } else {
          exchangeRate = returnData;
        }

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
          new Date(timestamp * 1000),
          "yyyy-MM-dd HH:mm:ss"
        ),
        timestamp,
        blockNumber,
      };
    }
  );

  historicalExchangeRates["dailyBlockData"] = formattedBlockData;

  console.log(
    JSON.stringify(historicalExchangeRates, (_, v) =>
      typeof v === "bigint" ? v.toString() : v
    )
  );
}

main();

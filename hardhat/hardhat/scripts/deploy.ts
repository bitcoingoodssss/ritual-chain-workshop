import { ethers } from "ethers";
import * as dotenv from "dotenv";
import { readFileSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

async function main() {
  const provider = new ethers.JsonRpcProvider("https://rpc.ritualfoundation.org");
  const privateKey = process.env.PRIVATE_KEY!;
  const wallet = new ethers.Wallet(privateKey, provider);

  console.log("部署账户:", wallet.address);

  const artifactPath = join(__dirname, "../artifacts/contracts/AIJudge.sol/AIJudge.json");
  const artifact = JSON.parse(readFileSync(artifactPath, "utf8"));

  const factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode, wallet);
  const contract = await factory.deploy();

  await contract.waitForDeployment();

  console.log("✅ AIJudge 部署成功！");
  console.log("合约地址:", await contract.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});

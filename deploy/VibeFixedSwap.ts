import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const deployFunction: DeployFunction = async function ({
  deployments,
  getNamedAccounts,
}: HardhatRuntimeEnvironment) {
  console.log("Running VibeFixedSwap deploy script");
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const { address } = await deploy("VibeFixedSwap", {
    from: deployer,
    log: true,
    deterministicDeployment: false,
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        init: {
          methodName: 'initialize',
          args: [
            (await deployments.get("VibeRoyalty")).address,
          ]
        }
      }
    },
  });

  console.log("VibeFixedSwap deployed at ", address);
};

export default deployFunction;

deployFunction.dependencies = [
    'VibeRoyalty'
];

deployFunction.tags = ["VibeFixedSwap"];

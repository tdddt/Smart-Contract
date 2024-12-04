require("@nomicfoundation/hardhat-toolbox");
require('dotenv').config();

const { PRIVATE_KEY } = process.env;

module.exports = {
  solidity: "0.8.27",
  networks: { 
    polygonAmoy: { 
      url: 'https://rpc-amoy.polygon.technology/', 
      accounts: [PRIVATE_KEY] 
    }
  }
};

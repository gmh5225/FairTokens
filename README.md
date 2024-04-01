# FairTokens - platform to launch tokens with aligned incentives

![image](imgs/fair-tokens.png)

## Overview

FairTokens reshape the usual fair tokens models, by creating tokens that are minted/burnt on demand when adding LPing and removing LP, which only require to add the anchor token (WETH, USDC..), and LP is initialized at a baseline price in Uniswap v3 1% pool. LPs can only remove at most what they initially put in, thus ensuring that traders will always find some liquidity to sell back into. As well as anyone can take part of LPing without the need to own the token, which reduce cost by 50% to take part of LPing to earn trading fees.

## Features

- rug-pulls prevention.
- establishing a baseline price.
- token buyers are assured to have liquidity to sell back into.
- anyone can take part of liquidity provision and earn trading fees.
- reducing cost of LPing by 50%.
- platform fees charged on trading fees.

## Drawbacks

- LPers might inccur impermanent loss.
- on LP removal, liquidity becomes realtively thinner.

## To do

- include built-in LP locker.

## Example on Testnet:

The following is an example for how the concept works on Sepolia:

- user 1: create token, uni v3 pool and initialize price 1:1 [tx](https://sepolia.etherscan.io/tx/0x396c5e18ef33f81c7badf9789c4c5c28016b607f2cb98837ef5406a4775eeb3d)
- user 1 adds 0.01 ETH [tx](https://sepolia.etherscan.io/tx/0x0ab229f7c00d62a555010b111f5c73d596173df5492ecf5c9fb456844559bc0e)
- user 2 buys 0.001ETH [tx](https://sepolia.etherscan.io/tx/0xbf4ed445a6ae9470482e2de5f9db231ef06556041e5a98a22cd69472bbdd532d)
- user 3 adds 0.01ETH [tx](https://sepolia.etherscan.io/tx/0xe19b684f173b151dc3ffe6f77a3168e3f5ebbf0f1f4bfd79680362e257f76538)
- user 2 sells tokens [tx](https://sepolia.etherscan.io/tx/0x37eacc803c1e9f93a4a5350943e7396fc71a4669de24a7f2c70cd0ea0f6dc75a)
- collect and distribute trading fees, takes 2 minutes to fully distribute among LPers [tx](https://sepolia.etherscan.io/tx/0xf7fec3d716c6db4840935b9fcdf4cf6f8a791e854f473b1d3c7a994e5cccf693)
- user 3 claims trading fees after 2 mins [tx](https://sepolia.etherscan.io/tx/0x3105e38046a105088f21da4b88e861a08a301abc1aaf3cf206f300d5106a54be)
- user 3 removes LP [tx](https://sepolia.etherscan.io/tx/0xc466b52a88913f188896e011556aa3886fdc5b420d74c194f05edc935d1024f7)
- user 1 claims trading fees [tx](https://sepolia.etherscan.io/tx/0xfec98aa7c46a5563f151920014e51ea3772c9c561f400a610eb0e6d508069220)
- user 1 removes LP, it has removed at most 0.1ETH which was has been put initially [tx](https://sepolia.etherscan.io/tx/0x0db7e0ee8edd5ce2f5f888bbc7bdf0864d7a547b0f0f09b83715d13bd5bbc03a )
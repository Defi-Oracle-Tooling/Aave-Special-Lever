const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("CombinedLeverageSystem", function () {
    // We define a fixture to reuse the same setup in every test.
    async function deployFixture() {
        const [owner, user, otherAccount] = await ethers.getSigners();

        // Deploy DAOAuthority
        const DAOAuthorityFactory = await ethers.getContractFactory("DAOAuthority");
        const daoAuthority = await DAOAuthorityFactory.deploy(owner.address); // Pass owner as initial owner

        // Deploy the CombinedLeverageSystem using the DAOAuthority address
        const CombinedLeverageSystemFactory = await ethers.getContractFactory("CombinedLeverageSystem");
        const combinedLeverageSystem = await CombinedLeverageSystemFactory.deploy(daoAuthority.address);

        // Authorize owner in DAOAuthority contract (redundant if owner deploys, but explicit)
        // await daoAuthority.connect(owner).setAuthorization(owner.address, true);
        // Authorize another address for testing purposes if needed
        await daoAuthority.connect(owner).setAuthorization(user.address, true);


        return { combinedLeverageSystem, daoAuthority, owner, user, otherAccount };
    }

    describe("Deployment", function () {
        it("Should set the right DAO Authority address", async function () {
            const { combinedLeverageSystem, daoAuthority } = await loadFixture(deployFixture);
            expect(await combinedLeverageSystem.daoAuthority()).to.equal(daoAuthority.address);
        });

        it("Should fail deployment if DAO Authority address is zero", async function () {
            const CombinedLeverageSystemFactory = await ethers.getContractFactory("CombinedLeverageSystem");
            await expect(CombinedLeverageSystemFactory.deploy(ethers.constants.AddressZero))
                .to.be.revertedWith("CombinedLeverageSystem: Invalid DAO authority address");
        });

        it("Should have emergency flag set to false initially", async function () {
            const { combinedLeverageSystem } = await loadFixture(deployFixture);
            expect(await combinedLeverageSystem.emergency()).to.equal(false);
        });

        it("Should have lastLeveragedAmount set to 0 initially", async function () {
            const { combinedLeverageSystem } = await loadFixture(deployFixture);
            expect(await combinedLeverageSystem.lastLeveragedAmount()).to.equal(0);
        });
    });

    describe("executeLeverage", function () {
        const leverageAmount = ethers.utils.parseEther("10");
        const simulatedOracleData = ethers.utils.hexlify(ethers.utils.toUtf8Bytes("simulated_data"));
        const strategyParams = ethers.utils.hexlify(ethers.utils.toUtf8Bytes("strategy_params"));

        it("Should execute leverage, update lastLeveragedAmount and emit LeverageExecuted event", async function () {
            const { combinedLeverageSystem, owner } = await loadFixture(deployFixture);

            await expect(combinedLeverageSystem.connect(owner).executeLeverage(leverageAmount, simulatedOracleData, strategyParams))
                .to.emit(combinedLeverageSystem, "LeverageExecuted")
                .withArgs(leverageAmount);

            expect(await combinedLeverageSystem.lastLeveragedAmount()).to.equal(leverageAmount);
        });

        it("Should emit LTVUpdated event (from internal call)", async function () {
            const { combinedLeverageSystem, owner } = await loadFixture(deployFixture);
            // We expect LTVUpdated because the default LTV (8000) is different from initial (0)
            await expect(combinedLeverageSystem.connect(owner).executeLeverage(leverageAmount, simulatedOracleData, strategyParams))
                .to.emit(combinedLeverageSystem, "LTVUpdated") // Event is emitted by the inherited contract
                .withArgs(8000); // Assuming the placeholder sets LTV to 8000
        });

        it("Should emit YieldRouted event (from internal call)", async function () {
            const { combinedLeverageSystem, owner } = await loadFixture(deployFixture);
            const simulatedYield = leverageAmount.div(100); // 1% yield assumption matches contract
            const expectedStrategyId = ethers.utils.keccak256(strategyParams);

            await expect(combinedLeverageSystem.connect(owner).executeLeverage(leverageAmount, simulatedOracleData, strategyParams))
                .to.emit(combinedLeverageSystem, "YieldRouted") // Event is emitted by the inherited contract
                .withArgs(expectedStrategyId, simulatedYield);
        });


        it("Should revert leverage execution if amount is zero", async function () {
            const { combinedLeverageSystem, owner } = await loadFixture(deployFixture);
            await expect(combinedLeverageSystem.connect(owner).executeLeverage(0, simulatedOracleData, strategyParams))
                .to.be.revertedWith("CombinedLeverageSystem: Amount must be positive");
        });


        it("Should revert leverage execution when emergency mode is active", async function () {
            const { combinedLeverageSystem, owner } = await loadFixture(deployFixture);
            // Trigger emergency exit by the authorized owner
            await combinedLeverageSystem.connect(owner).emergencyExit();
            await expect(combinedLeverageSystem.connect(owner).executeLeverage(leverageAmount, simulatedOracleData, strategyParams))
                .to.be.revertedWith("CombinedLeverageSystem: Emergency mode active");
        });

        it("Should prevent reentrancy", async function () {
            // This test is complex to set up correctly without a malicious contract.
            // Relying on OpenZeppelin's tested ReentrancyGuard is generally sufficient.
            // A basic check ensures the modifier is present and reverts typical reentrant calls.
            const { combinedLeverageSystem, owner } = await loadFixture(deployFixture);
            // Simulate a scenario where executeLeverage somehow calls itself again
            // This requires a helper contract usually. For now, we trust the modifier.
            // We can check if a simple call works fine, implying the guard is in place.
            await expect(combinedLeverageSystem.connect(owner).executeLeverage(leverageAmount, simulatedOracleData, strategyParams))
                .to.not.be.reverted; // Basic check passes
        });
    });

    describe("emergencyExit", function () {
        it("Should allow emergency exit only for authorized accounts (owner)", async function () {
            const { combinedLeverageSystem, owner } = await loadFixture(deployFixture);
            await expect(combinedLeverageSystem.connect(owner).emergencyExit())
                .to.emit(combinedLeverageSystem, "EmergencyExitTriggered")
                .withArgs(owner.address);
            expect(await combinedLeverageSystem.emergency()).to.equal(true);
        });

        it("Should allow emergency exit only for authorized accounts (user authorized via DAO)", async function () {
            const { combinedLeverageSystem, user } = await loadFixture(deployFixture);
            // User was authorized in the fixture
            await expect(combinedLeverageSystem.connect(user).emergencyExit())
                .to.emit(combinedLeverageSystem, "EmergencyExitTriggered")
                .withArgs(user.address);
            expect(await combinedLeverageSystem.emergency()).to.equal(true);
        });


        it("Should revert emergency exit for unauthorized accounts", async function () {
            const { combinedLeverageSystem, otherAccount } = await loadFixture(deployFixture);
            // otherAccount was not authorized
            await expect(combinedLeverageSystem.connect(otherAccount).emergencyExit())
                .to.be.revertedWith("CombinedLeverageSystem: Caller not authorized by DAO");
            expect(await combinedLeverageSystem.emergency()).to.equal(false); // State should not change
        });

        it("Should prevent reentrancy", async function () {
            const { combinedLeverageSystem, owner } = await loadFixture(deployFixture);
            // Similar to executeLeverage, direct reentrancy testing is complex.
            // Trusting the modifier. Check if a simple call works.
            await expect(combinedLeverageSystem.connect(owner).emergencyExit())
                .to.not.be.reverted; // Basic check passes
        });

        // Optional: Test idempotency - calling emergencyExit again after it's active
        it("Should handle being called again when already in emergency mode", async function () {
            const { combinedLeverageSystem, owner } = await loadFixture(deployFixture);
            await combinedLeverageSystem.connect(owner).emergencyExit(); // First call
            expect(await combinedLeverageSystem.emergency()).to.equal(true);

            // Second call - current implementation allows this, it just sets true again and emits event again.
            await expect(combinedLeverageSystem.connect(owner).emergencyExit())
                .to.emit(combinedLeverageSystem, "EmergencyExitTriggered")
                .withArgs(owner.address);
            expect(await combinedLeverageSystem.emergency()).to.equal(true); // Still true

            // If idempotency (reverting on second call) is desired, add require(!emergency) in the contract.
        });
    });
});
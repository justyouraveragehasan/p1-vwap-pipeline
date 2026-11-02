.PHONY: sim bit clean
sim:
	bash scripts/sim.sh tb_vwap
bit:
	bash scripts/build.sh
clean:
	rm -rf build xsim.dir *.jou *.log *.pb .Xil

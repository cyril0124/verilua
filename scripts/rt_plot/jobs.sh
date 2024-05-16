# Make sure you have already install <parallel>
# Usage: parallel < jobs.sh

# Add you jobs...
python3 rt_plot.py -p 12345 -t hit_slice_0 -x time -y hit_rate -i 10 > hit_slice_0.out 2>&1
# python3 rt_plot.py -p 12346 -t hit_slice_1 -x time -y hit_rate -i 10 > hit_slice_1.out 2>&1

python3 rt_plot.py -p 12355 -t hit_slice_0_a -x time -y hit_rate -i 10 > hit_slice_0_a.out 2>&1
# python3 rt_plot.py -p 12356 -t hit_slice_1_a -x time -y hit_rate -i 10 > hit_slice_1_a.out 2>&1

# python3 rt_plot.py -p 12365 -t hit_slice_0_c -x time -y hit_rate -i 10 > hit_slice_0_c.out 2>&1
# python3 rt_plot.py -p 12366 -t hit_slice_1_c -x time -y hit_rate -i 10 > hit_slice_1_c.out 2>&1

python3 rt_plot.py -p 12365 -t hit_slice_0_total_a -x time -y hit_rate -i 10 > hit_slice_0_total_a.out 2>&1
# python3 rt_plot.py -p 12366 -t hit_slice_1_total_a -x time -y hit_rate -i 10 > hit_slice_1_total_a.out 2>&1

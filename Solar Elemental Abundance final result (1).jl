Solar_Elemental_Abundance = [12.0, 10.94, 3.31, 1.44, 2.8, 8.56, 7.98, 8.77, 4.4, 8.15, 6.29, 7.55, 6.43, 7.59, 5.41, 7.16, 5.25, 6.5, 
                             5.14, 6.37, 3.07, 4.94, 3.89, 5.74, 5.52, 7.5, 4.95, 6.24, 4.292, 4.658, 3.126, 3.651, 2.355, 3.388, 
                             2.624, 3.312, 2.388, 2.944, 2.234, 2.624, 1.448, 1.985, NaN, 1.849, 1.139, 1.727, 1.261, 1.77, 0.828, 2.142, 
                             1.087, 2.253, 1.569, 2.302, 1.135, 2.209, 1.214, 1.638, 0.81, 1.492, NaN, 0.975, 0.548, 1.091, 0.341, 1.157, 
                             0.524, 0.977, 0.138, 0.965, 0.123, 0.8, -0.108, 0.676, 0.29, 1.399, 1.379, 1.703, 0.861, 1.186, 0.836, 
                             2.083, 0.712, NaN, NaN, NaN, NaN, NaN, NaN ,0.116, NaN, -0.461 ]


count = 0

for i in Solar_Elemental_Abundance
    print(i ," ")
    count += 1

end
    
println("\nnumber of elements listed: ", count)



# Derived from the results of Ekaterina Magg's 2022 paper, with the statistics from Katharina Lodders' 2002 paper.
# using thr equation: A_i = 1.57 + log10(N_i)

using PyPlot
using Korg

n = [0,1,2,3,4]


number = []

count = 0

for i in Solar_Elemental_Abundance
    count += 1
    push!(number, count)
end

label = []

count1 = 1

for i in 1:count
    push!(label, Korg.atomic_symbols[count1])
    count1 += 1
end
    

plt_1 = plt.figure(figsize=(22,8))
plt.scatter(number, Solar_Elemental_Abundance,s = 15, c = "blue")
plt.xlabel("Z (species)")
plt.ylabel("A(x)")
plt.yticks([-5.0,-2.5,0.0,1,2,3,4,5,6,7,8,9,10,11,12])

for i in range(1,length(number))
        plt.annotate(label[i],(number[i]-0.4,Solar_Elemental_Abundance[i]+0.2))
end



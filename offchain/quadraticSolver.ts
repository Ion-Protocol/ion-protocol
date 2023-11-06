// solves quadratic equation 
// (-b ± sqrt(b^2 - 4ac)) / 2a
// solidity input 
// bun quadraticSolver.ts a b c 

// quadraticSolver.ts

function addFixed(a: bigint, b: bigint): bigint {
  return a + b;
}

function subFixed(a: bigint, b: bigint): bigint {
  return a - b;
}

function mulFixed(a: bigint, b: bigint): bigint {
  return (a * b) / SCALE;
}

function divFixed(a: bigint, b: bigint): bigint {
  return (a * SCALE) / b;
}

function sqrtFixed(value: bigint): bigint {
  if (value < 0n) {
    throw new Error("Cannot take the square root of a negative number");
  }
  let z = value;
  let x = (value / 2n) + 1n;
  while (x < z) {
    z = x;
    x = (divFixed((addFixed(mulFixed(x, x), value)), (2n * x)));
  }
  return z;
}

function calculateZeroes(a: bigint, b: bigint, c: bigint, SCALE: bigint): bigint {
    const bSquared = mulFixed(b, b); 
    console.log("bSquared: ", bSquared);
    const ac = mulFixed(a, c); 
    console.log("ac: ", ac);
    const ac4 = mulFixed(4n * SCALE, ac); 
    console.log("ac4: ", ac4);
    const discriminant = subFixed(bSquared, ac4); 
    console.log("discriminant: ", discriminant);
    if (discriminant < 0n) {
        throw new Error("discriminant should not be negative"); 
    }

    const twoA = 2n * a;
    const sqrtDiscriminant = sqrtFixed(discriminant);
    console.log("sqrtDiscriminant: ", sqrtDiscriminant);
    console.log("sqrtDiscriminant * sqrtDiscriminant: ", mulFixed(sqrtDiscriminant, sqrtDiscriminant)); 
    const root1 = divFixed(subFixed(-b, sqrtDiscriminant), twoA);
    const root2 = divFixed(addFixed(-b, sqrtDiscriminant), twoA); // greater zero 

    const root = root1 > root2 ? root1 : root2; 

    if (root < 0) {
        throw new Error("the x-intercept should not be negative"); 
    }
    
    return root;
}

const args = process.argv.slice(2); // denary fixed point 
const a = BigInt(args[0]);
const b = BigInt(args[1]);
const c = BigInt(args[2]);
const SCALER = args[3]; // 27 
const SCALE = BigInt("1000000000000000000000000000"); // 1e27

const signedA = BigInt.asIntN(128, a); 
const signedB = BigInt.asIntN(128, b); 
const signedC = BigInt.asIntN(128, c); 

console.log("a, b, c, SCALER: ", a, b, c, SCALER);
console.log("signedA, signedB, signedC: ", signedA, signedB, signedC);
try {
    const root = calculateZeroes(signedA, signedB, signedC, SCALE)
    const rootObj = {
        root: root.toString()
    }; 
    
    const jsonRoots = JSON.stringify(rootObj);
    
    console.log(jsonRoots);
    
} catch (e) {
    console.log("Error calculating zeroes: ", e); 
}



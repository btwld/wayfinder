import { Calculator } from './calculator';

export const buildCalculator = () => {
  const calculator = new Calculator();
  return {
    divideSafely: (a: number, b: number) => calculator.divide(a, b),
  };
};

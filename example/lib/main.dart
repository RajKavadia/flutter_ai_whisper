import 'package:flutter/material.dart';

final CounterCubit counterCubit = CounterCubit();

void main() => runApp(const MyApp());

class CounterCubit {
  int _count = 0;
  int get count => _count;
  void setValue(int v) => _count = v;
  void increment() => _count++;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      routes: {
        '/': (_) => const HomePage(),
        '/profile': (_) => const Scaffold(body: Center(child: Text('Profile'))),
      },
      initialRoute: '/',
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _localCounter = 0;
  static int buildCount = 0;

  @override
  Widget build(BuildContext context) {
    buildCount++;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('count: ${counterCubit.count}'),
            Text('local: $_localCounter'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                counterCubit.increment();
                setState(() => _localCounter++);
              },
              child: const Text('increment'),
            ),
          ],
        ),
      ),
    );
  }
}
